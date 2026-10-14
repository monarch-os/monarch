local data = require("./data.luau")
local inFlight = false

local function render()
  barWidget.render(ui.glyph({ name = "robot", size = 16, color = "on_surface" }))
  local tooltip = {}
  for _, provider in ipairs(noctalia.state.get("providers") or {}) do
    local lines = {}
    local issue = data.error(provider)
    if issue ~= "" then lines[#lines + 1] = issue end
    for _, window in ipairs(data.windows(provider)) do
      lines[#lines + 1] = window.title .. ": " .. string.format("%.1f%% used", window.used)
    end
    local balance = data.balance(provider)
    if balance then lines[#lines + 1] = "Balance remaining: " .. balance end
    tooltip[#tooltip + 1] = { key = data.name(provider), value = table.concat(lines, "\n") }
  end
  local issue = noctalia.state.get("error") or ""
  if issue ~= "" then tooltip[#tooltip + 1] = { key = "Status", value = issue } end
  if #tooltip == 0 then tooltip[1] = { key = "Agents", value = "Waiting for provider data" } end
  barWidget.setTooltip(tooltip)
end

local function refresh()
  if inFlight then return end
  inFlight = true
  local started = noctalia.runAsync("/usr/bin/timeout 30s /usr/bin/codexbar usage --format json --json-only", function(result)
    inFlight = false
    local decoded = result and noctalia.json.decode(result.stdout or "")
    if type(decoded) == "table" then
      local providers = decoded.providers or (decoded.provider and { decoded }) or decoded
      if #providers > 0 then
        noctalia.state.set("providers", providers)
        noctalia.state.set("error", "")
        render()
        return
      end
      if result.exitCode == 0 then
        noctalia.state.set("providers", {})
        noctalia.state.set("error", "No enabled provider has reported usage")
        render()
        return
      end
    end
    noctalia.state.set("error", "CodexBar could not refresh; showing last known data")
    render()
  end, 30000)
  if started == false then
    inFlight = false
    noctalia.state.set("error", "CodexBar could not start; refresh to retry")
    render()
  end
end

function update() refresh() end
function onClick() noctalia.togglePanel("monarch/agents:details") end
function onRightClick() refresh() end
function onIpc(event)
  if event == "refresh" then refresh() end
end

noctalia.state.watch("command", function(value)
  if type(value) == "table" and value.action == "refresh" then refresh() end
end)
noctalia.setUpdateInterval(math.max(60, tonumber(noctalia.getConfig("refreshIntervalSec")) or 60) * 1000)
render()
refresh()
