--!strict
-- Repository/AUR update count and category color; hidden while offline or up to date.
-- The stream owns checking, localization and bounded tooltips.

local indicator = require("./indicator.luau")

local streamPid = nil
indicator.stream("monarch-update.sh", function(payload)
  if type(payload) == "table" and type(payload.pid) == "number"
    and payload.pid > 0 and payload.pid == math.floor(payload.pid) then
    streamPid = payload.pid
    return true
  end
  return false
end)

function onIpc(event)
  if event == "refresh" and streamPid then
    noctalia.runAsync("kill -USR1 " .. tostring(streamPid))
  end
end

function onClick()
  local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
  end
  noctalia.runAsync(quote(indicator.bin("monarch-launch-floating-terminal-with-presentation"))
    .. " --app-id=org.monarch.update " .. quote(quote(indicator.bin("monarch-update"))))
end
