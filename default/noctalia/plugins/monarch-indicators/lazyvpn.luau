--!strict
-- VPN status pill. Ports the v4 CustomButton that monarch-install-lazyvpn used
-- to splice into settings.json with jq — declaring it here instead means the
-- install and remove commands no longer have to edit the bar layout at all.
--
-- LazyVPN is install-on-demand, so the widget hides itself when the status
-- command is missing rather than being added and removed from the bar.
--
-- Polled, not streamed: monarch-lazyvpn-status is a one-shot command, matching
-- the v4 textIntervalMs = 5000.

local indicator = require("./indicator.luau")

-- Absolute paths: Noctalia's PATH does not contain Monarch's bin/ (see
-- indicator.bin).
local STATUS_CMD = indicator.bin("monarch-lazyvpn-status")
local POLL_MS = 5000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setGlyph("shield")
barWidget.setVisible(false)

local function apply(payload)
  local text = if type(payload) == "table" then payload.text else nil

  if type(text) ~= "string" or text == "" then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end

  barWidget.setText(text)
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
