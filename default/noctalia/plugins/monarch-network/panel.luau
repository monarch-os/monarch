--!nonstrict
-- The network panel. Port of quattro's omarchy.network panel: what you are
-- connected to, how well, the Wi-Fi band, the DNS provider, and the networks in
-- range. Enterprise networks join from here too, which the stock widget cannot.
--
-- Everything it knows comes from Monarch commands printing key<TAB>value, so
-- the logic that talks to NetworkManager stays in bash where it can be tested
-- without a radio. This file is presentation and sequencing only.
--
-- No keyboard navigation, unlike quattro's j/k model: v5's plugin UI gives a
-- tab order and `capture_keys`, not per-row focus, so rows are click targets.

local shared = require("./shared.luau")

local STATUS_CMD = shared.bin("monarch-network-status")
local BAND_CMD = shared.bin("monarch-wifi-band")
local LIST_CMD = shared.bin("monarch-wifi-list")
local JOIN_CMD = shared.bin("monarch-wifi-join")
local JOIN_EAP_CMD = shared.bin("monarch-wifi-enterprise")
local FORGET_CMD = shared.bin("monarch-wifi-forget")
local DISCONNECT_CMD = shared.bin("monarch-wifi-disconnect")
local RADIO_CMD = shared.bin("monarch-toggle-wifi")
local DNS_CMD = shared.bin("monarch-setup-dns")
local TERMINAL_CMD = shared.bin("monarch-launch-floating-terminal-with-presentation")
-- The monarch-dns package. Root-owned, and etc/sudoers.d/monarch-dns grants the
-- three fixed providers passwordless — which is the whole reason it is a
-- package: a grant may only ever name a path the user cannot rewrite.
local PACKAGED_DNS = "/usr/bin/monarch-dns"

local TEXT_WIDTH = 360
local DNS_PROVIDERS = { "Cloudflare", "Google", "DHCP", "Custom" }
-- Roughly the last half-minute of probes, at one per tick.
local PING_WINDOW = 24

local info = {}
local band = { band = "", selected = "auto", available = {} }
local networks = {}
local radioOn = true
local scanning = false
local loaded = false

-- The row opened for its actions, what was typed into its credential fields,
-- and the action currently in flight ("" when idle). One at a time on purpose:
-- joining two networks at once is not a thing, and a single token keeps every
-- button's disabled state derivable from one value.
local expanded = ""
local password = ""
local identity = ""
local busy = ""
local errorText = ""

-- Throughput is a delta between two samples and packet loss is a window of
-- them, so neither exists until the panel has polled twice. Both are cleared on
-- close, or a panel reopened an hour later divides an hour of traffic by a tick.
local sample = { iface = "", rx = 0, tx = 0, at = 0 }
local rxRate, txRate = 0, 0
local pings = {}
local pingIface = ""
local statusInFlight = false
local ticks = 0

-- Reads and writes both take a ticket: a refresh started before the last click
-- must not land its stale answer on top of the newer state.
local generation = 0

local render

local function formatBytes(count: number): string
  if count < 1024 then
    return string.format("%d B", math.floor(count))
  elseif count < 1024 * 1024 then
    return string.format("%.1f KB", count / 1024)
  elseif count < 1024 * 1024 * 1024 then
    return string.format("%.1f MB", count / (1024 * 1024))
  end
  return string.format("%.2f GB", count / (1024 * 1024 * 1024))
end

local function formatRate(perSecond: number): string
  return formatBytes(perSecond) .. "/s"
end

-- The counters only ever grow, until the interface changes or its driver resets
-- them — so a negative delta is a new counter, not negative traffic.
local function updateTransfer()
  local iface = info.iface or ""
  local rx = tonumber(info.rx_bytes) or 0
  local tx = tonumber(info.tx_bytes) or 0
  local now = noctalia.nowMs()

  if iface ~= sample.iface or sample.at == 0 then
    rxRate, txRate = 0, 0
  else
    local seconds = (now - sample.at) / 1000
    if seconds > 0 then
      rxRate = math.max(0, (rx - sample.rx) / seconds)
      txRate = math.max(0, (tx - sample.tx) / seconds)
    end
  end

  sample = { iface = iface, rx = rx, tx = tx, at = now }
end

-- One ping per poll, and a timed-out one prints an empty value rather than
-- vanishing. Keeping those misses in the window is the only way to report
-- packet loss at all: the probe has no -c count to derive it from, so the loss
-- is counted over time instead.
local function updatePings()
  local iface = info.iface or ""
  if iface ~= pingIface then
    pings = {}
    pingIface = iface
  end
  if info.internet_ping_ms == nil then
    return
  end

  local latency = tonumber(info.internet_ping_ms)
  table.insert(pings, (latency and latency >= 0) and latency or false)
  while #pings > PING_WINDOW do
    table.remove(pings, 1)
  end
end

local function pingAverage(): number
  local total, count = 0, 0
  for _, latency in ipairs(pings) do
    if latency then
      total += latency
      count += 1
    end
  end
  return count > 0 and total / count or -1
end

local function packetLoss(): number
  if #pings == 0 then
    return 0
  end

  local lost = 0
  for _, latency in ipairs(pings) do
    if not latency then
      lost += 1
    end
  end
  return math.floor(lost / #pings * 100 + 0.5)
end

-- Guarded rather than queued: a probe on a dead route waits out its ping
-- timeout, and a second tick behind it would only pile up.
local function pollStatus()
  if statusInFlight then
    return
  end

  statusInFlight = true
  local ticket = generation

  noctalia.runAsync(STATUS_CMD .. " --verbose", function(result)
    if ticket ~= generation then return end
    statusInFlight = false
    loaded = true
    info = (result and result.exitCode == 0) and shared.parseKeyValue(result.stdout or "") or {}
    updatePings()
    updateTransfer()
    render()
  end)
end

local function pollBand()
  local ticket = generation

  noctalia.runAsync(BAND_CMD, function(result)
    if ticket ~= generation then return end
    if result and result.exitCode == 0 then
      local parsed = shared.parseKeyValue(result.stdout or "")
      local available = {}
      for token in (parsed.available or ""):gmatch("%S+") do
        table.insert(available, token)
      end
      band = { band = parsed.band or "", selected = parsed.selected or "auto", available = available }
    else
      band = { band = "", selected = "auto", available = {} }
    end
    render()
  end)
end

local function refresh(rescan: boolean)
  generation += 1
  local ticket = generation

  if rescan then
    scanning = true
    render()
  end

  -- Whatever was in flight is already disowned by the bump above, so the guard
  -- it set must not keep this read from starting.
  statusInFlight = false
  pollStatus()
  pollBand()

  noctalia.runAsync(RADIO_CMD .. " status", function(result)
    if ticket ~= generation then return end
    local state = result and noctalia.json.decode(result.stdout or "")
    radioOn = not state or state.enabled ~= false
    render()
  end)

  -- The scan is the slow one; a rescan takes seconds and the rest of the panel
  -- must not wait on it.
  noctalia.runAsync(LIST_CMD .. (rescan and " --rescan" or ""), function(result)
    if ticket ~= generation then return end
    scanning = false
    networks = (result and result.exitCode == 0) and shared.parseNetworks(result.stdout or "") or {}
    render()
  end)
end

-- Every action ends the same way: clear the in-flight token, keep whatever the
-- command said on stderr, and re-read rather than guess at the new state.
local function runAction(token: string, command: string, fallback: string)
  if busy ~= "" then
    return
  end

  busy = token
  errorText = ""
  render()

  noctalia.runAsync(command, function(result)
    busy = ""
    if not result or result.exitCode ~= 0 then
      errorText = shared.errorFrom(result, fallback)
    else
      expanded = ""
      password = ""
      identity = ""
    end
    refresh(false)
  end)
end

local function setBand(target: string)
  if target == band.selected then
    return
  end
  runAction("band", BAND_CMD .. " " .. shared.shellQuote(target), "Could not change the Wi-Fi band")
end

local function dnsIsPackaged(): boolean
  return noctalia.fileExists(PACKAGED_DNS)
end

-- Custom always takes the terminal: it reads servers from stdin, and it is
-- deliberately outside the sudoers grant for exactly that reason. Without the
-- package the other three follow it there, since monarch-setup-dns writes under
-- /etc behind a sudo prompt this panel has no tty to answer.
local function setDns(provider: string)
  if provider ~= "Custom" and dnsIsPackaged() then
    runAction("dns", PACKAGED_DNS .. " " .. shared.shellQuote(provider),
      "Could not switch to " .. provider)
    return
  end

  noctalia.runAsync(TERMINAL_CMD .. " " .. DNS_CMD .. " " .. shared.shellQuote(provider))
  panel.close()
end

local function join(network)
  local token = "join:" .. network.ssid
  local fallback = "Could not join " .. network.ssid

  -- A saved profile already carries its credentials; nmcli reuses them when
  -- nothing follows the SSID, which is what makes a bare rejoin work — and it
  -- is the only way back onto an enterprise network, whose profile is built
  -- once and never rebuilt from here.
  if not network.saved and shared.isEnterprise(network) then
    if identity == "" then
      errorText = "Enter an identity for " .. network.ssid
      render()
      return
    end

    local command = JOIN_EAP_CMD .. " " .. shared.shellQuote(network.ssid)
      .. " " .. shared.shellQuote(identity)
    if password ~= "" then
      command ..= " " .. shared.shellQuote(password)
    end
    runAction(token, command, fallback)
    return
  end

  local command = JOIN_CMD .. " " .. shared.shellQuote(network.ssid)
  if not network.saved and shared.isSecured(network) and password ~= "" then
    command ..= " " .. shared.shellQuote(password)
  end
  runAction(token, command, fallback)
end

-- ── Rendering ────────────────────────────────────────────────────────────────

local function sectionHeader(text: string, trailing)
  local row = {
    ui.label({ text = text, fontSize = 11, fontWeight = "medium", color = "on_surface_variant", flexGrow = 1 }),
  }
  if trailing then
    table.insert(row, trailing)
  end
  return ui.row({ align = "center", gap = 8 }, row)
end

local function stat(label: string, value: string, color: string?): any
  return ui.row({ gap = 6, align = "center", flexGrow = 1 }, {
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = value, fontSize = 12, color = color or "on_surface", maxLines = 1 }),
  })
end

-- Two pairs to a line, as quattro's grid does: ten figures stacked one per line
-- would push the network list, which is what the panel is for, off the bottom.
local function statRow(left, right): any
  return ui.row({ gap = 16 }, { left, right })
end

local function connectionBlock(): { any }
  if not info.iface or info.iface == "" then
    return {
      ui.label({
        text = loaded and "Not connected" or "Reading the route…",
        fontSize = 12,
        color = "on_surface_variant",
      }),
    }
  end

  local address = info.ip or ""
  if address ~= "" and info.prefix and info.prefix ~= "" then
    address ..= "/" .. info.prefix
  end

  -- The gateway carries its own latency: how far the router is says which side
  -- of it a bad internet ping is coming from, and it costs no extra line.
  local gateway = info.gateway or ""
  if gateway ~= "" and info.router_ping_ms and info.router_ping_ms ~= "" then
    gateway ..= "  ·  " .. info.router_ping_ms .. " ms"
  end

  local latency = "—"
  if #pings > 0 then
    local average = pingAverage()
    latency = average < 0 and "Timeout"
      or (average < 10 and string.format("%.1f ms", average) or string.format("%.0f ms", average))
  end

  local loss = packetLoss()
  -- Both halves of the pair go red, or a loss figure alone reads as a rendering
  -- quirk rather than as the reason the latency beside it is untrustworthy.
  local lossColor = loss > 0 and "error" or nil
  local counted = info.rx_bytes ~= nil

  local linkValue, sideLabel, sideValue = "", "Signal", ""
  if info.type == "wifi" then
    linkValue = shared.trim(info.bitrate or "")
    if info.signal_dbm and info.signal_dbm ~= "" then
      sideValue = info.signal_dbm .. " dBm"
    end
  else
    -- A virtual or unplugged NIC reports -1, which is "unknown", not a speed.
    local speed = tonumber(info.speed or "")
    linkValue = (speed and speed > 0) and (speed .. " Mb/s") or ""
    sideLabel = "Duplex"
    sideValue = info.duplex or ""
  end

  local function shown(value: string): string
    return value ~= "" and value or "—"
  end

  return {
    statRow(
      stat("Ping", latency, lossColor),
      stat("Packet loss", #pings > 0 and (loss .. "%") or "—", lossColor)
    ),
    statRow(
      stat("Receiving", counted and formatRate(rxRate) or "—"),
      stat("Sending", counted and formatRate(txRate) or "—")
    ),
    statRow(
      stat("Downloaded", counted and formatBytes(tonumber(info.rx_bytes) or 0) or "—"),
      stat("Uploaded", counted and formatBytes(tonumber(info.tx_bytes) or 0) or "—")
    ),
    statRow(
      stat(info.iface, shown(address)),
      stat("Gateway", shown(gateway))
    ),
    statRow(
      stat("Link", shown(linkValue)),
      stat(sideLabel, shown(sideValue))
    ),
  }
end

local function bandSection(): { any }
  -- Nothing to choose and nothing pinned means nothing worth showing, exactly
  -- as upstream hides its band section; a pin stays visible even on a network
  -- answering on one band, or it could not be cleared from here.
  if info.type ~= "wifi" or (#band.available < 2 and band.selected == "auto") then
    return {}
  end

  local pills = {}
  for _, choice in ipairs({ "auto", table.unpack(band.available) }) do
    table.insert(pills, ui.button({
      text = shared.bandLabel(choice),
      -- Outline rather than ghost on the ones not in force: a ghost button with
      -- no border reads as a caption, and these are all choices.
      variant = band.selected == choice and "primary" or "outline",
      controlSize = "sm",
      enabled = busy == "",
      onClick = function()
        setBand(choice)
      end,
    }))
  end

  local note = band.selected == "auto"
      and (band.band ~= "" and ("Automatic — on " .. shared.bandLabel(band.band)) or "Automatic")
    or ("Pinned to " .. shared.bandLabel(band.selected))

  return {
    ui.separator({}),
    sectionHeader("WI-FI BAND"),
    ui.row({ gap = 8, align = "center" }, pills),
    ui.label({ text = busy == "band" and "Reconnecting…" or note, fontSize = 11, color = "on_surface_variant" }),
  }
end

local function dnsSection(): { any }
  local pills = {}

  for _, provider in ipairs(DNS_PROVIDERS) do
    table.insert(pills, ui.button({
      text = provider,
      variant = info.dns == provider and "primary" or "outline",
      controlSize = "sm",
      enabled = busy == "",
      onClick = function()
        setDns(provider)
      end,
    }))
  end

  return {
    ui.separator({}),
    sectionHeader("DNS PROVIDER"),
    ui.row({ gap = 8, align = "center" }, pills),
    ui.label({
      text = if busy == "dns"
        then "Applying…"
        elseif dnsIsPackaged() then "Custom opens a terminal — it asks for the servers."
        else "Opens a terminal — changing DNS needs root.",
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }
end

local function networkActions(network): any
  local joining = busy == "join:" .. network.ssid

  if network.connected then
    return ui.row({ gap = 8, align = "center" }, {
      ui.button({
        text = busy == "disconnect" and "Disconnecting…" or "Disconnect",
        variant = "outline",
        controlSize = "sm",
        enabled = busy == "",
        onClick = function()
          runAction("disconnect", DISCONNECT_CMD, "Could not disconnect")
        end,
      }),
      ui.button({
        text = "Forget",
        variant = "outline",
        controlSize = "sm",
        enabled = busy == "",
        onClick = function()
          runAction("forget:" .. network.ssid, FORGET_CMD .. " " .. shared.shellQuote(network.ssid),
            "Could not forget " .. network.ssid)
        end,
      }),
    })
  end

  local row = {}
  local credentials = {}
  local enterprise = shared.isEnterprise(network)

  -- A saved network needs no field: NetworkManager still holds its secret, and
  -- asking again would invite the user to overwrite a working one by mistake.
  if not network.saved and shared.isSecured(network) then
    if enterprise then
      table.insert(credentials, ui.input({
        key = "id:" .. network.ssid,
        placeholder = "Identity (user@domain)",
        focus = true,
        flexGrow = 1,
        onChange = function(value)
          identity = value
        end,
      }))
    end

    table.insert(credentials, ui.input({
      key = "pw:" .. network.ssid,
      placeholder = "Password",
      password = true,
      focus = not enterprise,
      flexGrow = 1,
      onChange = function(value)
        password = value
      end,
      onSubmit = function(value)
        password = value
        join(network)
      end,
    }))
  end

  table.insert(row, ui.button({
    text = joining and "Connecting…" or "Connect",
    variant = "primary",
    controlSize = "sm",
    enabled = busy == "",
    onClick = function()
      join(network)
    end,
  }))

  if network.saved then
    table.insert(row, ui.button({
      text = "Forget",
      variant = "outline",
      controlSize = "sm",
      enabled = busy == "",
      onClick = function()
        runAction("forget:" .. network.ssid, FORGET_CMD .. " " .. shared.shellQuote(network.ssid),
          "Could not forget " .. network.ssid)
      end,
    }))
  end

  -- PEAP asks two questions, and two fields beside a button do not fit this
  -- width; a pre-shared key keeps its single line.
  if #credentials > 1 then
    return ui.column({ gap = 6 }, {
      ui.column({ gap = 6 }, credentials),
      ui.row({ gap = 8, align = "center" }, row),
    })
  end

  local line = {}
  for _, node in ipairs(credentials) do
    table.insert(line, node)
  end
  for _, node in ipairs(row) do
    table.insert(line, node)
  end

  return ui.row({ gap = 8, align = "center" }, line)
end

local function networkRow(network): any
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({
        name = shared.signalGlyph(network.signal),
        color = network.connected and "primary" or "on_surface",
      }),
      ui.label({
        text = network.ssid,
        fontSize = 13,
        color = network.connected and "primary" or "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
      shared.isSecured(network) and ui.glyph({ name = "lock", color = "on_surface_variant" }) or ui.spacer({}),
      ui.label({ text = network.signal .. "%", fontSize = 11, color = "on_surface_variant" }),
    }),
  }

  if expanded == network.ssid then
    table.insert(children, networkActions(network))
  end

  return ui.column({
    gap = 6,
    onClick = function()
      if busy ~= "" then
        return
      end
      expanded = expanded == network.ssid and "" or network.ssid
      password = ""
      identity = ""
      errorText = ""
      render()
    end,
  }, children)
end

local function networkList(): { any }
  local rows = {}

  if not radioOn then
    return { ui.label({ text = "Wi-Fi is off", fontSize = 12, color = "on_surface_variant" }) }
  end

  if #networks == 0 then
    return {
      ui.label({
        text = loaded and "No networks in range" or "Scanning…",
        fontSize = 12,
        color = "on_surface_variant",
      }),
    }
  end

  for _, network in ipairs(networks) do
    table.insert(rows, networkRow(network))
  end

  return rows
end

function render()
  local body = {}

  -- Hero actions. Sharing needs a Wi-Fi connection to share; the speed test
  -- needs any route at all.
  local hero = {}
  if info.type == "wifi" then
    table.insert(hero, ui.button({
      text = "Share",
      glyph = "qrcode",
      variant = "outline",
      controlSize = "sm",
      onClick = "onShareClicked",
    }))
  end
  if info.iface and info.iface ~= "" then
    table.insert(hero, ui.button({
      text = "Speed test",
      glyph = "activity-heartbeat",
      variant = "outline",
      controlSize = "sm",
      onClick = "onSpeedTestClicked",
    }))
  end
  table.insert(hero, ui.spacer({ flexGrow = 1 }))
  table.insert(hero, ui.label({ text = "Wi-Fi", fontSize = 12, color = "on_surface_variant" }))
  table.insert(hero, ui.toggle({
    checked = radioOn,
    onChange = "onRadioChanged",
  }))

  table.insert(body, ui.row({ gap = 8, align = "center" }, hero))
  table.insert(body, ui.column({ gap = 4 }, connectionBlock()))

  for _, node in ipairs(bandSection()) do
    table.insert(body, node)
  end
  for _, node in ipairs(dnsSection()) do
    table.insert(body, node)
  end

  table.insert(body, ui.separator({}))
  table.insert(body, sectionHeader(
    scanning and "SCANNING WI-FI…" or "NETWORKS",
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      enabled = not scanning and busy == "",
      onClick = "onRescanClicked",
    })
  ))

  if errorText ~= "" then
    table.insert(body, ui.label({
      text = errorText,
      fontSize = 12,
      color = "error",
      maxWidth = TEXT_WIDTH,
    }))
  end

  local subtitle = info.ssid or info.iface or ""

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = "Network", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = subtitle, fontSize = 12, color = "on_surface_variant", maxLines = 1 }),
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.scroll({ flexGrow = 1, gap = 10 }, (function()
      local all = {}
      for _, node in ipairs(body) do
        table.insert(all, node)
      end
      for _, node in ipairs(networkList()) do
        table.insert(all, node)
      end
      return all
    end)()),
  }))
end

-- Every open re-reads: the panel is only right about the connection the machine
-- is on at the moment it is summoned. The list comes from NetworkManager's
-- cache, so it paints at once; the refresh button is the one that scans.
function onOpen(_context)
  loaded = false
  expanded = ""
  password = ""
  identity = ""
  busy = ""
  errorText = ""
  ticks = 0
  sample = { iface = "", rx = 0, tx = 0, at = 0 }
  rxRate, txRate = 0, 0
  pings = {}
  pingIface = ""
  panel.setWantsSecondTicks(true)
  render()
  refresh(false)
end

-- The tick is what makes the throughput and the loss window exist at all; the
-- rest of the panel would be happy with a single read on open.
function update()
  ticks += 1
  pollStatus()

  -- Band availability only moves when a scan turns up a new BSSID, and reading
  -- it costs several nmcli calls, so it does not ride every tick.
  if ticks % 4 == 0 then
    pollBand()
  end
end

function onClose()
  generation += 1
  panel.setWantsSecondTicks(false)
  statusInFlight = false
  password = ""
  identity = ""
  busy = ""
end

function onCloseClicked()
  panel.close()
end

function onRescanClicked()
  refresh(true)
end

function onShareClicked()
  noctalia.togglePanel("monarch/wifi-qr:panel")
end

function onSpeedTestClicked()
  noctalia.togglePanel("monarch/network:speedtest")
end

function onRadioChanged(checked)
  runAction("radio", RADIO_CMD .. (checked and " on" or " off"), "Could not switch the Wi-Fi radio")
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
