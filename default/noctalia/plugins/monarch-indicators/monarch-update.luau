--!strict
-- Repository/AUR update count and category color; hidden while offline or up to date.
-- The stream owns checking, localization and bounded tooltips.

local indicator = require("./indicator.luau")

indicator.stream("monarch-update.sh")

function onClick()
  local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
  end
  noctalia.runAsync(quote(indicator.bin("monarch-launch-floating-terminal-with-presentation"))
    .. " --app-id=org.monarch.update " .. quote(quote(indicator.bin("monarch-update"))))
end
