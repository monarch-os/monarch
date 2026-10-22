--!strict
-- Shows a moon while night light is forced on; hidden otherwise. Replaces the
-- stock v5 `nightlight` widget, which is always visible.
--
-- Tracks the forced state only — the schedule is a separate concern that stays
-- out of the bar. bin/monarch-toggle-nightlight owns the runtime marker.

local indicator = require("./indicator.luau")
local runtimeToggle = require("./runtime-toggle.luau")

local COMMAND = "monarch-toggle-nightlight"
local refresh = runtimeToggle.start("nightlight", "󰖔", "Night light on - restore day temperature")

function update()
  refresh()
end

function onIpc(event)
  if event == "refresh" then
    refresh()
  end
end

function onClick()
  noctalia.runAsync(indicator.bin(COMMAND), function()
    update()
  end)
end
