local source = assert(arg[1])
local pending, results, actions = {}, {}, {}
local loads = 0
local model = {
  fromArray = function(tree) return tree end,
  search = function(menu, query, guards)
    return guards['custom.action:w'] == false and {} or {{id = 'custom.action'}}
  end,
  parentOf = function() return 'root' end,
  labelOf = function(menu, id) return menu.entries[id].label end,
}
local environment = setmetatable({
  require = function() return model end,
  noctalia = {
    getenv = function() return nil end,
    json = {decode = function(payload) return payload end},
    runAsync = function(command, callback)
      if command:find('monarch%-menu %-%-state') then
        loads = loads + 1
        pending[#pending + 1] = callback
      else
        actions[#actions + 1] = command
      end
    end,
  },
  launcher = {setResults = function(query, list) results = {query = query, list = list} end},
}, {__index = _G})
assert(loadfile(source, 't', environment))()

local function complete(label, guards, exitCode)
  local callback = assert(table.remove(pending, 1), 'query must request current menu state')
  callback({exitCode = exitCode or 0, stdout = {
    tree = {entries = {['custom.action'] = {label = label, action = 'echo ' .. label, disabled = 'installed'}}},
    guards = guards or {},
  }})
end

environment.onQuery('first')
complete('first')
assert(results.list[1].title == 'first')
environment.onQuery('first')
complete('updated')
assert(results.list[1].title == 'updated', 'reopening the same query must reload user extensions')
environment.onActivate('custom.action')
assert(actions[1]:find('updated'), 'activation must run the updated action')
print('ok - reopening reloads the tree and activates the current command')

environment.onQuery('installed')
complete('updated', {['custom.action:d'] = true})
assert(#results.list == 0, 'installed actions must disappear after package state changes')
environment.onQuery('removed')
complete('updated', {['custom.action:w'] = false})
assert(#results.list == 0, 'visibility guards must be reevaluated')
print('ok - reopening refreshes package and visibility guards')

local before = loads
environment.onQuery('a')
environment.onQuery('ab')
environment.onQuery('abc')
assert(loads == before + 1, 'in-flight queries must share one state request')
complete('stale')
assert(#results.list == 0, 'superseded results must not be published')
assert(loads == before + 2, 'coalesced queries must request the latest state')
complete('current')
assert(results.query == 'abc' and results.list[1].title == 'current')
print('ok - typing coalesces requests and ignores superseded asynchronous results')

environment.onQuery('failure')
complete('ignored', {}, 1)
assert(#results.list == 0, 'failed refresh must not retain actionable stale results')
local count = #actions
environment.onActivate('custom.action')
assert(#actions == count, 'failed refresh must not execute a stale action')
environment.onQuery('retry')
complete('recovered')
assert(results.list[1].title == 'recovered')
print('ok - failures clear stale actions and the next query retries')
