--!strict
-- Shows a crossed-out bell while do-not-disturb is on; hidden otherwise.
--
-- Unlike caffeine and nightlight, this one has no Monarch-side bookkeeping
-- behind it: `notification-dnd-status` reports the shell's real state, so it cannot
-- drift — including when DND is toggled from the control center.
--
-- The v5 `notifications` widget is not a substitute: it carries DND on its bell,
-- but it is a notification-history button first and is always visible.

local indicator = require("./indicator.luau")

local COMMAND = "monarch-toggle-notification-silencing"
local POLL_MS = 2000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setVisible(false)

function update()
  -- Noctalia exposes no DND subscription; keep control-center changes responsive.
  noctalia.runAsync("/usr/bin/noctalia msg notification-dnd-status", function(result)
    if result.exitCode ~= 0 or not result.stdout:match("^%s*on%s*$") then
      barWidget.clearTooltip()
      barWidget.setVisible(false)
      return
    end
    barWidget.setText("󰂛")
    barWidget.setColor("primary")
    barWidget.setTooltip("Do not disturb - allow notifications")
    barWidget.setVisible(true)
  end)
end

function onClick()
  noctalia.runAsync(indicator.bin(COMMAND), function()
    update()
  end)
end
