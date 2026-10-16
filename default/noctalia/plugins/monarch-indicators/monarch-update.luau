--!strict
-- Repository/AUR update count and category color; hidden only after a complete
-- up-to-date check. The stream owns checking, localization and bounded tooltips.

local indicator = require("./indicator.luau")

indicator.stream("monarch-update.sh")

function onClick()
  local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
  end
  noctalia.runAsync(quote(indicator.bin("monarch-launch-floating-terminal-with-presentation"))
    .. " " .. quote(quote(indicator.bin("monarch-update"))))
end
