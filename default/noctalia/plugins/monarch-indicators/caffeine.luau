--!strict
-- Shows a cup while caffeine (the idle inhibitor) is on; hidden otherwise.
-- Replaces the stock v5 `caffeine` widget, which is always visible.
--
local indicator = require("./indicator.luau")
local runtimeToggle = require("./runtime-toggle.luau")

local COMMAND = "monarch-toggle-idle"
local refresh = runtimeToggle.start("caffeine", "󰅶", "Caffeine on - allow idle lock")

function update()
  refresh()
end

function onIpc(event)
  if event == "refresh" then
    refresh()
  end
end

-- The pill is only on screen while caffeine is on, so a click can only ever
-- turn it back off.
function onClick()
  noctalia.runAsync(indicator.bin(COMMAND), function()
    update()
  end)
end
