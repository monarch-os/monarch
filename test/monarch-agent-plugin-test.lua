local root = arg[1]
local data = dofile(root .. "/data.luau")
local provider = {
  provider = "synthetic",
  rateWindowLabels = { primary = "Five-hour quota", secondary = "Weekly tokens", tertiary = "Search hourly" },
  usage = {
    primary = { usedPercent = 0.04 },
    secondary = { usedPercent = 10 },
    tertiary = { usedPercent = 120 },
  },
}
local windows = data.windows(provider)
assert(#windows == 3)
assert(windows[3].title == "Search hourly")
assert(windows[3].used == 100)
assert(data.error({ error = { message = "Sign in required" } }) == "Sign in required")
assert(#data.windows({}) == 0)
assert(#data.windows({ usage = { extraRateWindows = {
  { usageKnown = false, window = { usedPercent = 0, resetsAt = "2026-10-15T00:00:00Z" } },
} } }) == 0)
assert(#data.windows({ usage = { primary = { usageKnown = false, usedPercent = 0 } } }) == 0)
assert(data.balance({ usage = { providerCost = { balance = 0, currencyCode = "USD" } } }) == "0 USD")

local state = { providers = { provider } }
local tree, tooltip, command
local watchers = {}
local originalRequire = require
require = function(path)
  assert(path == "./data.luau")
  return data
end
ui = setmetatable({}, { __index = function(_, kind)
  return function(props, children) return { kind = kind, props = props, children = children or {} } end
end })
noctalia = {
  getConfig = function() return nil end,
  setUpdateInterval = function() end,
  json = { decode = function() return { provider } end },
  state = {
    get = function(key) return state[key] end,
    set = function(key, value)
      state[key] = value
      if watchers[key] then watchers[key](value) end
    end,
    watch = function(key, callback) watchers[key] = callback end,
  },
  runAsync = function(value, callback)
    command = value
    if callback then callback({ stdout = "[]", exitCode = 1 }) end
  end,
  togglePanel = function(value) assert(value == "monarch/agents:details") end,
}
barWidget = {
  render = function(value) tree = value end,
  setTooltip = function(value) tooltip = value end,
}
dofile(root .. "/widget.luau")
assert(tree.kind == "glyph" and tree.props.name == "robot")
assert(tooltip[1].value:find("Search hourly", 1, true))
assert(command:find("/usr/bin/codexbar", 1, true))
onClick()
local attempts = 0
noctalia.runAsync = function()
  attempts = attempts + 1
  return false
end
onRightClick()
onRightClick()
assert(attempts == 2, "A failed launch must not block subsequent refreshes")
assert(state.error ~= "")
noctalia.runAsync = function(value) command = value; return true end
panel = { render = function(value) tree = value end, close = function() end }
dofile(root .. "/panel.luau")
onOpen()
assert(tree.kind == "column")
local function contains(node, text)
  if node.props.text == text then return true end
  for _, child in ipairs(node.children) do
    if contains(child, text) then return true end
  end
  return false
end
state.providers = { { provider = "grok", usage = { providerCost = { balance = 0, currencyCode = "USD" } } } }
watchers.providers()
assert(contains(tree, "Balance remaining: 0 USD"))
assert(not contains(tree, "No quota reported"))
onManageProviders()
assert(command:find("/usr/bin/monarch-agent-usage manage", 1, true))
require = originalRequire
print("Monarch Agents plugin tests passed")
