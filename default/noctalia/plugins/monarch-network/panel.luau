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
-- The Monarch runtime installs this path root-owned, and monarch-settings
-- grants the three fixed providers passwordless in etc/sudoers.d/monarch-dns.
local PACKAGED_DNS = "/usr/bin/monarch-dns"

local TEXT_WIDTH = 360
local DNS_PROVIDERS = {
  { name = "DHCP", tooltip = "Use the DNS servers DHCP hands out" },
  { name = "Cloudflare", tooltip = "Set DNS to Cloudflare" },
  { name = "Google", tooltip = "Set DNS to Google" },
  { name = "Custom", tooltip = "Set custom DNS servers — opens a terminal" },
}
-- Roughly the last half-minute of probes, at one per tick.
local PING_WINDOW = 24
-- Rescans while the panel is open, which is why it has no refresh button.
local RESCAN_TICKS = 10
local PHRASE_TICKS = 3
local PHRASES = {
  "Wiring bits",
  "Handling packets",
  "Sorting frames",
  "Hauling bytes",
  "Routing crumbs",
  "Counting collisions",
  "Bending light",
}

local info = {}
local band = { band = "", selected = "auto", available = {} }
local networks = {}
local radioOn = true
local radioPresent = true
local scanning = false
local loaded = false

-- One action at a time, so every button's disabled state derives from one value.
-- The two SSIDs say which row owns the token and the message; empty means the
-- panel itself — the band, the DNS or the radio.
local promptSsid = ""
local password = ""
local identity = ""
local busy = ""
local busySsid = ""
local failedSsid = ""
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
local phrase = 1

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

-- One decimal below 10 ms and none above: the third decimal a local gateway
-- reports is measurement noise, not precision.
local function formatMs(ms: number): string
  return (ms < 10 and string.format("%.1f", ms) or string.format("%.0f", ms)) .. " ms"
end

-- A virtual or unplugged NIC reports -1, which is "unknown", not a speed.
local function formatLinkSpeed(mbps: string?): string
  local speed = tonumber(mbps or "")
  if not speed or speed <= 0 then
    return ""
  elseif speed >= 1000 then
    return string.format(speed % 1000 == 0 and "%.0f Gb/s" or "%.1f Gb/s", speed / 1000)
  end
  return string.format("%d Mb/s", speed)
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

local function connectedNetwork()
  for _, network in ipairs(networks) do
    if network.connected then
      return network
    end
  end
  return nil
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

local function pollNetworks(rescan: boolean)
  local ticket = generation

  if rescan then
    scanning = true
    render()
  end

  noctalia.runAsync(LIST_CMD .. (rescan and " --rescan" or ""), function(result)
    if ticket ~= generation then return end
    scanning = false
    -- The last good list stands when a sweep fails: NetworkManager refuses a
    -- rescan too close behind the last one, and blanking on that reads as a
    -- neighbourhood that emptied out.
    if result and result.exitCode == 0 then
      networks = shared.parseNetworks(result.stdout or "")
    end
    render()
  end)
end

local function refresh(rescan: boolean)
  generation += 1
  local ticket = generation

  -- Whatever was in flight is already disowned by the bump above, so the guard
  -- it set must not keep this read from starting.
  statusInFlight = false
  pollStatus()
  pollBand()

  noctalia.runAsync(RADIO_CMD .. " status", function(result)
    if ticket ~= generation then return end
    local state = result and noctalia.json.decode(result.stdout or "")
    radioOn = not state or state.enabled ~= false
    radioPresent = not state or state.present ~= false
    render()
  end)

  pollNetworks(rescan)
end

-- Every action ends the same way: clear the in-flight token, keep whatever the
-- command said on stderr, and re-read rather than guess at the new state.
local function runAction(kind: string, ssid: string, command: string, fallback: string)
  if busy ~= "" then
    return
  end

  busy, busySsid = kind, ssid
  failedSsid, errorText = "", ""
  render()

  noctalia.runAsync(command, function(result)
    busy, busySsid = "", ""
    if not result or result.exitCode ~= 0 then
      errorText = shared.errorFrom(result, fallback)
      failedSsid = ssid
    else
      promptSsid, password, identity = "", "", ""
    end
    refresh(false)
  end)
end

local function setBand(target: string)
  if target == band.selected then
    return
  end
  runAction("band", "", BAND_CMD .. " " .. shared.shellQuote(target), "Could not change the Wi-Fi band")
end

local function dnsIsPackaged(): boolean
  return noctalia.fileExists(PACKAGED_DNS)
end

-- Custom always takes the terminal: it reads servers from stdin, and it is
-- deliberately outside the sudoers grant for exactly that reason. Without the
-- package the other three follow it there, where monarch-setup-dns can install
-- it behind a sudo prompt this panel has no tty to answer.
local function setDns(provider: string)
  if provider ~= "Custom" and dnsIsPackaged() then
    runAction("dns", "", PACKAGED_DNS .. " " .. shared.shellQuote(provider),
      "Could not switch to " .. provider)
    return
  end

  noctalia.runAsync(TERMINAL_CMD .. " " .. DNS_CMD .. " " .. shared.shellQuote(provider))
  panel.close()
end

local function join(network)
  local fallback = "Could not join " .. network.ssid

  -- A saved profile already carries its credentials; nmcli reuses them when
  -- nothing follows the SSID, which is what makes a bare rejoin work — and it
  -- is the only way back onto an enterprise network, whose profile is built
  -- once and never rebuilt from here.
  if not network.saved and shared.isEnterprise(network) then
    if identity == "" then
      failedSsid, errorText = network.ssid, "Enter an identity"
      render()
      return
    end

    local command = JOIN_EAP_CMD .. " " .. shared.shellQuote(network.ssid)
      .. " " .. shared.shellQuote(identity)
    if password ~= "" then
      command ..= " " .. shared.shellQuote(password)
    end
    runAction("connect", network.ssid, command, fallback)
    return
  end

  local command = JOIN_CMD .. " " .. shared.shellQuote(network.ssid)
  if not network.saved and shared.isSecured(network) and password ~= "" then
    command ..= " " .. shared.shellQuote(password)
  end
  runAction("connect", network.ssid, command, fallback)
end

local function forget(network)
  runAction("forget", network.ssid, FORGET_CMD .. " " .. shared.shellQuote(network.ssid),
    "Could not forget " .. network.ssid)
end

local function activate(network)
  if busy ~= "" then
    return
  end

  if network.connected then
    runAction("disconnect", network.ssid, DISCONNECT_CMD, "Could not disconnect")
    return
  end

  if network.saved or not shared.isSecured(network) then
    join(network)
    return
  end

  promptSsid = promptSsid == network.ssid and "" or network.ssid
  password, identity = "", ""
  failedSsid, errorText = "", ""
  render()
end

-- ── Rendering ────────────────────────────────────────────────────────────────

local function sectionHeader(key: string, text: string, trailing): any
  local row = {
    ui.label({
      key = "text",
      text = text,
      fontSize = 11,
      fontWeight = "medium",
      color = "on_surface_variant",
      flexGrow = 1,
    }),
  }
  if trailing then
    table.insert(row, trailing)
  end
  return ui.row({ key = key, align = "center", gap = 8 }, row)
end

local function stat(label: string, value: string, color: string?): any
  return ui.row({ key = label, gap = 6, align = "center", flexGrow = 1 }, {
    ui.label({ key = "l", text = label, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ key = "v", text = value, fontSize = 12, color = color or "on_surface", maxLines = 1 }),
  })
end

-- Two pairs to a line, as quattro's grid does: eight stacked figures would push
-- the network list off the bottom.
local function statRow(key: string, left, right): any
  return ui.row({ key = key, gap = 16 }, { left, right })
end

local function heroGlyph(): string
  if info.type == "wifi" then
    local current = connectedNetwork()
    return shared.signalGlyph(current and current.signal or 100)
  elseif info.type == "ethernet" then
    return "ethernet"
  end
  return "wifi-off"
end

local function heroTitle(): string
  if info.type == "wifi" then
    return (info.ssid ~= nil and info.ssid ~= "") and info.ssid or "Wi-Fi"
  elseif info.type == "ethernet" then
    local speed = formatLinkSpeed(info.speed)
    return speed ~= "" and ("Ethernet (" .. speed .. ")") or "Ethernet"
  elseif info.iface ~= nil and info.iface ~= "" then
    return info.iface
  end
  return loaded and "Disconnected" or "Network"
end

local function heroCaption(): string
  if not loaded then
    return ""
  elseif info.iface == nil or info.iface == "" then
    return "NOT CONNECTED"
  end
  return PHRASES[phrase]:upper()
end

local function hero(): any
  local children = {
    ui.glyph({ key = "icon", name = heroGlyph(), size = 26, color = "on_surface" }),
    ui.column({ key = "labels", gap = 2, flexGrow = 1 }, {
      ui.label({ key = "title", text = heroTitle(), fontSize = 15, fontWeight = "bold", maxLines = 1 }),
      ui.label({
        key = "caption",
        text = heroCaption(),
        fontSize = 10,
        fontWeight = "medium",
        color = "on_surface_variant",
        maxLines = 1,
      }),
    }),
  }

  if info.type == "wifi" then
    table.insert(children, ui.button({
      key = "qr",
      glyph = "qrcode",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Show the Wi-Fi QR code",
      onClick = "onShareClicked",
    }))
  end
  if info.iface ~= nil and info.iface ~= "" then
    table.insert(children, ui.button({
      key = "speed",
      glyph = "activity-heartbeat",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Run a speed test",
      onClick = "onSpeedTestClicked",
    }))
  end
  if radioPresent then
    table.insert(children, ui.toggle({ key = "radio", checked = radioOn, onChange = "onRadioChanged" }))
  end

  return ui.row({ key = "hero", align = "center", gap = 12 }, children)
end

local function shown(value: string?): string
  return (value ~= nil and value ~= "") and value or "—"
end

local function connectionBlock(): { any }
  if info.iface == nil or info.iface == "" then
    return {}
  end

  local latency = "—"
  if #pings > 0 then
    local average = pingAverage()
    latency = average < 0 and "Timeout" or formatMs(average)
  end

  local loss = packetLoss()
  -- Both halves of the pair go red, or a loss figure alone reads as a rendering
  -- quirk rather than as the reason the latency beside it is untrustworthy.
  local lossColor = loss > 0 and "error" or nil
  local counted = info.rx_bytes ~= nil

  return {
    statRow("stat-ping",
      stat("Ping", latency, lossColor),
      stat("Packet loss", #pings > 0 and (loss .. "%") or "—", lossColor)
    ),
    statRow("stat-rate",
      stat("Receiving", counted and formatRate(rxRate) or "—"),
      stat("Sending", counted and formatRate(txRate) or "—")
    ),
    statRow("stat-total",
      stat("Downloaded", counted and formatBytes(tonumber(info.rx_bytes) or 0) or "—"),
      stat("Uploaded", counted and formatBytes(tonumber(info.tx_bytes) or 0) or "—")
    ),
    statRow("stat-route",
      stat("IP address", shown(info.ip)),
      stat("Gateway", shown(info.gateway))
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

  -- Under Automatic there are no pills to name the live band, so the header does.
  local title = "WI-FI BAND"
  if band.selected == "auto" and band.band ~= "" then
    title ..= ": " .. band.band .. "GHZ"
  end

  local nodes = {
    ui.separator({ key = "band-rule" }),
    sectionHeader("band-head", title, ui.row({ key = "auto", align = "center", gap = 8 }, {
      ui.label({
        key = "label",
        text = busy == "band" and "SWITCHING…" or "AUTOMATIC",
        fontSize = 11,
        fontWeight = "medium",
        color = "on_surface_variant",
      }),
      ui.toggle({
        key = "toggle",
        checked = band.selected == "auto",
        enabled = busy == "",
        onChange = "onBandAutoChanged",
      }),
    })),
  }

  if band.selected ~= "auto" then
    local pills = {}
    for _, choice in ipairs(band.available) do
      table.insert(pills, ui.button({
        key = choice,
        text = shared.bandLabel(choice),
        variant = band.selected == choice and "primary" or "outline",
        controlSize = "sm",
        flexGrow = 1,
        enabled = busy == "",
        onClick = function()
          setBand(choice)
        end,
      }))
    end
    table.insert(nodes, ui.row({ key = "band-pills", gap = 6 }, pills))
  end

  return nodes
end

local function dnsSection(): { any }
  local pills = {}

  for _, provider in ipairs(DNS_PROVIDERS) do
    table.insert(pills, ui.button({
      key = provider.name,
      text = provider.name,
      variant = info.dns == provider.name and "primary" or "outline",
      controlSize = "sm",
      flexGrow = 1,
      enabled = busy == "",
      tooltip = dnsIsPackaged() and provider.tooltip or (provider.tooltip .. " — opens a terminal"),
      onClick = function()
        setDns(provider.name)
      end,
    }))
  end

  return {
    ui.separator({ key = "dns-rule" }),
    sectionHeader("dns-head", busy == "dns" and "DNS PROVIDER — APPLYING…" or "DNS PROVIDER"),
    ui.row({ key = "dns-pills", gap = 6 }, pills),
  }
end

local function rowStatus(network): (string, string)
  local ssid = network.ssid

  if busySsid == ssid then
    if busy == "connect" then
      return "Connecting…", "on_surface_variant"
    elseif busy == "disconnect" then
      return "Disconnecting…", "on_surface_variant"
    elseif busy == "forget" then
      return "Forgetting…", "on_surface_variant"
    end
  end

  if failedSsid == ssid then
    return errorText, "error"
  elseif network.connected then
    return "Connected", "on_surface"
  end
  return "", "on_surface_variant"
end

local function credentials(network): any
  local fields = {}
  local enterprise = shared.isEnterprise(network)

  if enterprise then
    table.insert(fields, ui.input({
      key = "identity",
      placeholder = "Identity (user@domain)",
      focus = true,
      flexGrow = 1,
      onChange = function(value)
        identity = value
      end,
    }))
  end

  table.insert(fields, ui.input({
    key = "password",
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

  table.insert(fields, ui.button({
    key = "connect",
    glyph = "check",
    variant = "primary",
    controlSize = "sm",
    enabled = busy == "",
    tooltip = "Connect",
    onClick = function()
      join(network)
    end,
  }))

  -- Two fields beside a button do not fit this width; one does.
  if enterprise then
    return ui.column({ key = "credentials", gap = 6 }, fields)
  end
  return ui.row({ key = "credentials", gap = 6, align = "center" }, fields)
end

local function networkRow(network): any
  local status, statusColor = rowStatus(network)

  -- One slot at the right edge, a lock or the way off. Quattro swaps the two on
  -- hover; nothing here is cheap to redraw on hover, so the row says which it is.
  local trailing
  if network.saved and not network.connected then
    trailing = ui.button({
      key = "forget",
      glyph = "circle-x",
      variant = "ghost",
      controlSize = "sm",
      enabled = busy == "",
      tooltip = "Forget this network",
      onClick = function()
        forget(network)
      end,
    })
  elseif shared.isSecured(network) then
    trailing = ui.glyph({ key = "lock", name = "lock", color = "on_surface_variant" })
  else
    trailing = ui.spacer({ key = "pad", width = 20 })
  end

  local children = {
    ui.row({
      key = "line",
      gap = 10,
      align = "center",
      paddingH = 8,
      paddingV = 6,
      radius = 8,
      fill = network.connected and "surface_variant" or nil,
      onClick = function()
        activate(network)
      end,
    }, {
      ui.glyph({
        key = "signal",
        name = shared.signalGlyph(network.signal),
        color = network.connected and "primary" or "on_surface",
      }),
      ui.column({ key = "name", gap = 1, flexGrow = 1 }, {
        ui.label({
          key = "ssid",
          text = network.ssid,
          fontSize = 13,
          color = network.connected and "primary" or "on_surface",
          maxLines = 1,
        }),
        ui.label({
          key = "status",
          text = status,
          visible = status ~= "",
          fontSize = 11,
          color = statusColor,
          maxWidth = TEXT_WIDTH,
          maxLines = 1,
        }),
      }),
      trailing,
    }),
  }

  if promptSsid == network.ssid then
    table.insert(children, credentials(network))
  end

  return ui.column({ key = "net:" .. network.ssid, gap = 6 }, children)
end

local function networkList(): { any }
  if not radioPresent then
    return {}
  elseif not radioOn then
    return { ui.label({ key = "off", text = "Wi-Fi is off", fontSize = 12, color = "on_surface_variant" }) }
  elseif #networks == 0 then
    return {
      ui.label({
        key = "empty",
        text = loaded and "No networks in range" or "Scanning…",
        fontSize = 12,
        color = "on_surface_variant",
      }),
    }
  end

  local rows = {}
  local group = nil

  for _, network in ipairs(shared.sortNetworks(networks)) do
    if network.saved ~= group then
      group = network.saved
      table.insert(rows, sectionHeader(
        group and "group-known" or "group-other",
        group and "KNOWN NETWORKS" or "OTHER NETWORKS"
      ))
    end
    table.insert(rows, networkRow(network))
  end

  return rows
end

function render()
  local body = { hero() }

  for _, node in ipairs(connectionBlock()) do
    table.insert(body, node)
  end
  for _, node in ipairs(bandSection()) do
    table.insert(body, node)
  end
  for _, node in ipairs(dnsSection()) do
    table.insert(body, node)
  end

  if errorText ~= "" and failedSsid == "" then
    table.insert(body, ui.label({
      key = "error",
      text = errorText,
      fontSize = 12,
      color = "error",
      maxWidth = TEXT_WIDTH,
    }))
  end

  if radioPresent then
    table.insert(body, ui.separator({ key = "list-rule" }))
    if scanning then
      table.insert(body, sectionHeader("scanning", "SCANNING WI-FI…"))
    end
  end

  table.insert(body, ui.scroll({ key = "list", flexGrow = 1, gap = 6 }, networkList()))

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, body))
end

-- Every open re-reads: the panel is only right about the connection the machine
-- is on at the moment it is summoned. The list comes from NetworkManager's
-- cache, so it paints at once; the tick below is what rescans.
function onOpen(_context)
  loaded = false
  promptSsid = ""
  password = ""
  identity = ""
  busy, busySsid = "", ""
  failedSsid, errorText = "", ""
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
  if radioPresent and ticks % RESCAN_TICKS == 0 then
    pollNetworks(true)
  end
  if ticks % PHRASE_TICKS == 0 then
    phrase = phrase % #PHRASES + 1
    render()
  end
end

function onClose()
  generation += 1
  panel.setWantsSecondTicks(false)
  statusInFlight = false
  password = ""
  identity = ""
  busy, busySsid = "", ""
end

function onShareClicked()
  noctalia.togglePanel("monarch/wifi-qr:panel")
end

function onSpeedTestClicked()
  noctalia.togglePanel("monarch/network:speedtest")
end

function onRadioChanged(checked)
  runAction("radio", "", RADIO_CMD .. (checked and " on" or " off"), "Could not switch the Wi-Fi radio")
end

-- Switching Automatic off has to commit to something, so it pins the band the
-- radio already landed on — the one the header is showing.
function onBandAutoChanged(checked)
  if checked then
    setBand("auto")
  else
    setBand(band.band ~= "" and band.band or band.available[1] or "auto")
  end
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    if promptSsid ~= "" then
      promptSsid, password, identity = "", "", ""
      render()
      return
    end
    panel.close()
  end
end
