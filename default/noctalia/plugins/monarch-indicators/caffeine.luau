--!strict
-- Shows a cup while caffeine (the idle inhibitor) is on; hidden otherwise.
-- Replaces the stock v5 `caffeine` widget, which is always visible.
--
-- Polled rather than streamed: the state is a one-shot question to
-- monarch-toggle-idle, which owns it. Two seconds is short enough that a
-- keybinding press looks immediate, and clicks refresh without waiting for the
-- next tick. The shell's own caffeine OSD fires instantly either way.

local indicator = require("./indicator.luau")

local COMMAND = "monarch-toggle-idle"
local POLL_MS = 2000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setVisible(false)

function update()
  indicator.pollToggle(COMMAND, "󰅶")
end

-- The pill is only on screen while caffeine is on, so a click can only ever
-- turn it back off.
function onClick()
  noctalia.runAsync(indicator.bin(COMMAND), function()
    update()
  end)
end
