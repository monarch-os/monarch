--!strict
-- Shows the pending-update count; hidden when the system is up to date.
-- Ports the v4 CustomButton whose leftClickExec opened the update TUI.

local indicator = require("./indicator.luau")

indicator.stream("monarch-update.sh")

function onClick()
  noctalia.runAsync(indicator.bin("monarch-launch-floating-terminal-with-presentation") .. " monarch-update")
end
