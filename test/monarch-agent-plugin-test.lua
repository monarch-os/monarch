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
  togglePanel = function(value) assert(value == "monarch/agent:details") end,
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
panel = { render = function(value) tree = value end, close = function() end }
dofile(root .. "/panel.luau")
onOpen()
assert(tree.kind == "column")
onManageProviders()
assert(command:find("/usr/bin/monarch-agent-usage manage", 1, true))
require = originalRequire
print("Monarch Agent plugin tests passed")
