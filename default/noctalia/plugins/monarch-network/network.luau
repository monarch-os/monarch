--!nonstrict
-- The bar pill. Wired or wireless, how good the signal is, and — on Wi-Fi — the
-- band, coloured while that band is pinned rather than merely chosen.
--
-- Stock Noctalia shows the connection type and nothing else; quattro's pill
-- carries the link speed. The band is what Monarch has that neither does, and
-- it is the one number worth a glance on a router that puts every band behind
-- one name.

local shared = require("./shared.luau")

local STATUS_CMD = shared.bin("monarch-network-status")
local BAND_CMD = shared.bin("monarch-wifi-band")
local POLL_MS = 10000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setGlyph("wifi-off")

local function bandForFreq(freq: string): string
  local mhz = tonumber(freq:match("^%d+") or "")
  if not mhz then
    return ""
  end
  if mhz >= 2400 and mhz < 2500 then
    return "2.4"
  elseif mhz >= 4900 and mhz < 5925 then
    return "5"
  elseif mhz >= 5925 and mhz < 7125 then
    return "6"
  end
  return ""
end

local function showDisconnected()
  barWidget.setGlyph("wifi-off")
  barWidget.setText("")
  barWidget.setColor("on_surface_variant")
  barWidget.setGlyphColor("on_surface_variant")
  barWidget.setTooltip("No network")
end

local function showEthernet(device: string)
  -- `plug` is a wall socket: in a network widget it reads as power. `ethernet`
  -- is an RJ45 port, which is what quattro's own wired glyph draws.
  barWidget.setGlyph("ethernet")
  barWidget.setText("")
  barWidget.setColor("on_surface")
  barWidget.setGlyphColor("on_surface")
  barWidget.setTooltip("Wired — " .. device)
end

-- The pin is read separately because the bare status line is the cheap one and
-- says nothing about it; only Wi-Fi pays for the second call.
local function showWifi(ssid: string, signal: string, freq: string)
  local band = bandForFreq(freq)

  barWidget.setGlyph(shared.signalGlyph(tonumber(signal) or 0))
  barWidget.setText(band)
  barWidget.setVisible(true)

  noctalia.runAsync(BAND_CMD, function(result)
    local pinned = ""
    if result and result.exitCode == 0 then
      local status = shared.parseKeyValue(result.stdout or "")
      if status.selected and status.selected ~= "auto" then
        pinned = status.selected
      end
    end

    -- Glyph and text both, or the pill reads as half-lit.
    local role = pinned ~= "" and "primary" or "on_surface"
    barWidget.setColor(role)
    barWidget.setGlyphColor(role)

    local detail = ssid
    if signal ~= "" then
      detail ..= " — " .. signal .. "%"
    end
    if pinned ~= "" then
      detail ..= ", pinned to " .. shared.bandLabel(pinned)
    elseif band ~= "" then
      detail ..= ", on " .. shared.bandLabel(band)
    end
    barWidget.setTooltip(detail)
  end)
end

function update()
  noctalia.runAsync(STATUS_CMD, function(result)
    if not result or result.exitCode ~= 0 then
      showDisconnected()
      return
    end

    -- type<TAB>name<TAB>signal<TAB>freq, always four fields.
    local line = (result.stdout or ""):match("^[^\n]*") or ""
    local kind, name, signal, freq = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")

    if kind == "wifi" then
      showWifi(name, signal, freq)
    elseif kind == "ethernet" then
      showEthernet(name)
    else
      showDisconnected()
    end
    barWidget.setVisible(true)
  end)
end

function onClick()
  noctalia.togglePanel("monarch/network:panel")
end

-- The stock widget's job, kept one click away rather than dropped: Noctalia's
-- own network page still has settings this panel does not mirror.
function onRightClick()
  noctalia.runAsync(shared.bin("monarch-launch-wifi"))
end
