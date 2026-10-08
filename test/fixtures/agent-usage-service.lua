local root = assert(arg[1])
local function read(path)
  local handle = assert(io.open(path))
  local text = handle:read('*a')
  handle:close()
  return text
end

local function loadLuau(text, environment)
  text = text:gsub(': {%s*[^}]+%s*}%??', '')
    :gsub(': string%??', ''):gsub(': boolean', ''):gsub(': number', ''):gsub(': any', '')
    :gsub('if type%(entry%) == "table" then entry.name else entry', '(type(entry) == "table" and entry.name or entry)')
    :gsub('if #advising > 0 then noctalia.nowMs%(%) %+ 30000 else 0', '(#advising > 0 and noctalia.nowMs() + 30000 or 0)')
    :gsub('if plan ~= "" then name %.%. " · " %.%. plan else name', '(plan ~= "" and name .. " · " .. plan or name)')
  return assert(load(text, 'agents fixture', 't', environment))()
end

local disabled = {'claude', '../invalid'}
local records = {
  ['claude.json'] = {id = 'claude', ready = true, retryAdvised = true},
  ['codex.json'] = {id = 'codex', ready = true},
  ['alias.json'] = {id = 'claude', ready = true},
}
local state, commands = {}, {}
local noctalia = {
  getenv = function(key) return key == 'XDG_STATE_HOME' and '/state' or nil end,
  expandPath = function() return '/home/test/.local/state' end,
  getConfig = function() return nil end,
  setUpdateInterval = function() end,
  nowMs = function() return 1000000 end,
  listDir = function(path)
    if path == '/state/monarch/agents/disabled' then return disabled end
    return {'claude.json', 'codex.json', 'alias.json'}
  end,
  readFile = function(path) return records[path:match('([^/]+)$')] end,
  json = {decode = function(record) return record end},
  state = {set = function(key, value) state[key] = value end},
  runAsync = function(command, callback)
    table.insert(commands, command)
    callback({exitCode = 0, stderr = ''})
    return true
  end,
}
local environment = setmetatable({noctalia = noctalia}, {__index = _G})
local shared = read(root .. '/agents.luau'):match('^(.-)function M.markPath')
local agents = loadLuau(shared .. '\nreturn M', environment)
agents.worstPercent = function(records) return #records end
agents.shellQuote = function(value) return "'" .. value .. "'" end
environment.require = function() return agents end
loadLuau(read(root .. '/service.luau'), environment)

environment.update()
assert(#state['agents.records'] == 1 and state['agents.records'][1].id == 'codex',
  'disabled agents must be hidden by file name and record identity')
assert(commands[1]:find("%-%-except 'claude'"), 'older installed wrappers must receive the exclusion')
assert(not commands[1]:find('invalid'), 'invalid marker names must never become collector arguments')
environment.onIpc('refresh')
assert(commands[2]:find('%-%-force') and commands[2]:find("%-%-except 'claude'"),
  'forced refresh must preserve the preference')

disabled = {}
environment.onIpc('refresh')
assert(#state['agents.records'] == 3, 'reenabling must reveal retained records without deleting history')
assert(not commands[3]:find('%-%-except'), 'reenabling must allow collection again')
print('ok - agent preferences hide records and stop collection across refreshes')

local mathWithClamp = setmetatable({clamp = function(value, low, high)
  return math.max(low, math.min(high, value))
end}, {__index = math})
environment.math = mathWithClamp
environment.M = agents
agents.timestamp = function(value) return tonumber(value) end
local percentFunction = read(root .. '/agents.luau'):match('(function M.limitPercent.-\nend)')
loadLuau(percentFunction .. '\nreturn M', environment)
local tooltip
environment.barWidget = {
  clearTooltip = function() tooltip = nil end,
  setVisible = function() end,
  setGlyph = function() end,
  setGlyphColor = function() end,
  setColor = function() end,
  setTooltip = function(value) tooltip = value end,
}
noctalia.state.get = function(key) return state[key] end
noctalia.state.watch = function() end
state['agents.records'] = {{id = 'codex', limits = {
  {label = 'Elapsed', percent = 0.95, resetsAt = '999'},
  {label = 'Boundary', percent = 0.95, resetsAt = '1000'},
  {label = 'Current', percent = 0.95, resetsAt = '1001'},
}}}
loadLuau(read(root .. '/widget.luau'), environment)
assert(tooltip:find('Elapsed: 0%%') and tooltip:find('Boundary: 0%%') and tooltip:find('Current: 95%%'),
  'the actual bar tooltip must normalize elapsed quotas without changing current ones')
print('ok - bar tooltip applies quota expiry consistently')
