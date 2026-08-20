--!nonstrict
-- The network panel. Port of quattro's omarchy.network panel: what you are
-- connected to, the Wi-Fi band, the DNS provider, and the networks in range.
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

local info = {}
local band = { band = "", selected = "auto", available = {} }
local networks = {}
local radioOn = true
local scanning = false
local loaded = false

-- The row opened for its actions, the text typed into its passphrase field, and
-- the action currently in flight ("" when idle). One at a time on purpose:
-- joining two networks at once is not a thing, and a single token keeps every
-- button's disabled state derivable from one value.
local expanded = ""
local password = ""
local busy = ""
local errorText = ""

-- Reads and writes both take a ticket: a refresh started before the last click
-- must not land its stale answer on top of the newer state.
local generation = 0

local render

local function refresh(rescan: boolean)
  generation += 1
  local ticket = generation

  if rescan then
    scanning = true
    render()
  end

  noctalia.runAsync(STATUS_CMD .. " --verbose", function(result)
    if ticket ~= generation then return end
    loaded = true
    info = (result and result.exitCode == 0) and shared.parseKeyValue(result.stdout or "") or {}
    render()
  end)

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
  local command = JOIN_CMD .. " " .. shared.shellQuote(network.ssid)
  -- A saved profile already carries its secret; nmcli reuses it when no
  -- password follows, which is what makes a bare rejoin work.
  if not network.saved and shared.isSecured(network) and password ~= "" then
    command ..= " " .. shared.shellQuote(password)
  end
  runAction("join:" .. network.ssid, command, "Could not join " .. network.ssid)
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

local function detailRow(label: string, value: string)
  return ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = value, fontSize = 12, color = "on_surface" }),
  })
end

local function connectionBlock(): { any }
  local rows = {}

  if info.ip and info.ip ~= "" then
    local address = info.ip
    if info.prefix and info.prefix ~= "" then
      address ..= "/" .. info.prefix
    end
    table.insert(rows, detailRow(info.iface or "Interface", address))
  end

  if info.type == "wifi" then
    if info.bitrate and shared.trim(info.bitrate) ~= "" then
      table.insert(rows, detailRow("Link", shared.trim(info.bitrate)))
    end
  elseif info.type == "ethernet" then
    -- A virtual or unplugged NIC reports -1, which is "unknown", not a speed.
    local speed = tonumber(info.speed or "")
    if speed and speed > 0 then
      table.insert(rows, detailRow("Link", speed .. " Mb/s"))
    end
  end

  if info.internet_ping_ms and info.internet_ping_ms ~= "" then
    local latency = info.internet_ping_ms .. " ms"
    if info.router_ping_ms and info.router_ping_ms ~= "" then
      latency = info.router_ping_ms .. " / " .. latency
    end
    table.insert(rows, detailRow("Ping (router / internet)", latency))
  end

  if #rows == 0 then
    table.insert(rows, ui.label({ text = "Not connected", fontSize = 12, color = "on_surface_variant" }))
  end

  return rows
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

  -- A saved network needs no field: NetworkManager still holds its secret, and
  -- asking again would invite the user to overwrite a working one by mistake.
  if not network.saved and shared.isSecured(network) then
    table.insert(row, ui.input({
      key = "pw:" .. network.ssid,
      placeholder = "Password",
      password = true,
      focus = true,
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

  return ui.row({ gap = 8, align = "center" }, row)
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
  busy = ""
  errorText = ""
  render()
  refresh(false)
end

function onClose()
  generation += 1
  password = ""
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
