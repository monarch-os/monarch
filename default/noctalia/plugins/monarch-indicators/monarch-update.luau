--!strict
-- Shows available updates or a failed online check; hidden while offline or up to date.
-- Ports the v4 CustomButton whose leftClickExec opened the update TUI.

local indicator = require("./indicator.luau")

indicator.stream("monarch-update.sh")

function onClick()
  noctalia.runAsync(indicator.bin("monarch-launch-floating-terminal-with-presentation") .. " monarch-update")
end
