--!strict
-- VPN status pill. Ports the v4 CustomButton that monarch-install-lazyvpn used
-- to splice into settings.json with jq — declaring it here instead means the
-- install and remove commands no longer have to edit the bar layout at all.
--
-- LazyVPN is install-on-demand, so the widget hides itself when the status
-- command is missing rather than being added and removed from the bar. It also
-- hides while the VPN is simply off — only a live tunnel or a killswitch left
-- blocking traffic is worth a pill.
--
-- Polled, not streamed: monarch-lazyvpn-status is a one-shot command, matching
-- the v4 textIntervalMs = 5000.

local indicator = require("./indicator.luau")

-- monarch-lazyvpn-status comes from the monarch-lazyvpn package (/usr/bin), not
-- from the repo's bin/ — see indicator.pkgBin. The launcher below does come from
-- bin/, hence the two different resolvers.
local STATUS_CMD = indicator.pkgBin("monarch-lazyvpn-status")
local POLL_MS = 5000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setGlyph("shield")
barWidget.setVisible(false)

-- monarch-lazyvpn-status emits one glyph for every visible state and puts the
-- state in `class`, modelled on the LazyVPN-for-Omarchy waybar module. The
-- colour is this plugin's job — Omarchy does it in waybar CSS, which v5 has no
-- equivalent of.
--
-- `ks-blocking` is the one that matters: no tunnel, but the killswitch is still
-- loaded and dropping every packet, so the pill turns red instead of vanishing.
-- Plain `disconnected` sends empty text and collapses the widget, which is what
-- retired the permanently-visible unlocked padlock.
local function colorForClass(class)
  if class == "ks-blocking" or class == "error" then
    return "error"
  end
  return "primary"
end

local function apply(payload)
  local text = if type(payload) == "table" then payload.text else nil

  if type(text) ~= "string" or text == "" then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end

  barWidget.setText(text)
  barWidget.setColor(colorForClass(payload.class))
  barWidget.setVisible(true)

  local tooltip = payload.tooltip
  if type(tooltip) == "string" and tooltip ~= "" then
    barWidget.setTooltip(tooltip)
  else
    barWidget.clearTooltip()
  end
end

function update()
  if not noctalia.fileExists(STATUS_CMD) then
    barWidget.setVisible(false)
    return
  end

  noctalia.runAsync(STATUS_CMD, function(result)
    if result.exitCode ~= 0 then
      barWidget.setVisible(false)
      return
    end
    local payload = noctalia.json.decode(result.stdout)
    if payload then
      apply(payload)
    else
      barWidget.setVisible(false)
    end
  end)
end

function onClick()
  noctalia.runAsync(indicator.bin("monarch-launch-floating-terminal-with-presentation") .. " monarch-lazyvpn")
end
