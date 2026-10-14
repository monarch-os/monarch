local inFlight = false
local startedAt = 0

local function refresh()
  if inFlight and os.time() - startedAt < 130 then return end
  inFlight = true
  startedAt = os.time()
  local started = noctalia.runStream("/usr/bin/monarch-agent-usage-fetch", function(line)
    inFlight = false
    local result = noctalia.json.decode(line)
    if type(result) == "table" and type(result.providers) == "table" then
      if #result.providers > 0 or result.ok == true then
        noctalia.state.set("providers", result.providers)
        noctalia.state.set("error", #result.providers > 0 and "" or "ui.no_usage")
        return
      end
    end
    noctalia.state.set("error", "ui.refresh_failed")
  end)
  if started == false then
    inFlight = false
    noctalia.state.set("error", "ui.launch_failed")
  end
end

function update() refresh() end
function onIpc(event)
  if event == "refresh" then refresh() end
end
noctalia.state.watch("command", function(value)
  if type(value) == "table" and value.action == "refresh" then refresh() end
end)
noctalia.setUpdateInterval(math.max(60, tonumber(noctalia.getConfig("refreshIntervalSec")) or 60) * 1000)
refresh()
