--!strict
-- Shows a moon while night light is forced on; hidden otherwise. Replaces the
-- stock v5 `nightlight` widget, which is always visible.
--
-- Tracks the forced state only — the schedule is a separate concern that stays
-- out of the bar. See caffeine.luau for the polling rationale and
-- bin/monarch-toggle-nightlight for who owns the state.

local indicator = require("./indicator.luau")

local COMMAND = "monarch-toggle-nightlight"
local POLL_MS = 2000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setVisible(false)

function update()
  indicator.pollToggle(COMMAND, "󰖔")
end

function onClick()
  noctalia.runAsync(indicator.bin(COMMAND), function()
    update()
  end)
end
