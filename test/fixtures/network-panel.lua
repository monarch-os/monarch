local handle = assert(io.open(assert(arg[1])))
local source = handle:read('*a')
handle:close()
source = source:gsub(': {%s*[^}]+%s*}%??', '')
  :gsub(': %(string, string%)', '')
  :gsub(': string%??', ''):gsub(': boolean', ''):gsub(': number', ''):gsub(': any', '')
  :gsub('([%w_]+) %+%= ', '%1 = %1 + ')
  :gsub('([%w_]+) %.%.= ', '%1 = %1 .. ')

local scanCallbacks, rendered, failRadio = {}, nil, false
local activeStatus, interfaceRecords = {}, {}
local checkCallback, checkCalls, portalCalls = nil, 0, 0
local shared = {
  bin = function(name) return name end,
  parseKeyValue = function(value) return value end,
  parseNetworks = function(value) return value end,
  sortNetworks = function(value) return value end,
  signalGlyph = function() return 'wifi' end,
  bandLabel = function(value) return value end,
  errorFrom = function(result, fallback) return result.stderr or fallback end,
}
local ui = setmetatable({}, {__index = function(_, kind)
  return function(properties, children) return {kind = kind, properties = properties, children = children} end
end})
local environment = setmetatable({
  require = function() return shared end,
  ui = ui,
  panel = {render = function(tree) rendered = tree end, setWantsSecondTicks = function() end},
  noctalia = {
    nowMs = function() return 1000 end,
    fileExists = function() return false end,
    json = {decode = function(value) return value end},
    runAsync = function(command, callback)
      if command == 'monarch-wifi-list --rescan' then
        scanCallbacks[#scanCallbacks + 1] = callback
      elseif command == 'monarch-network-check' then
        checkCalls = checkCalls + 1
        checkCallback = callback
      elseif command == 'monarch-network-captive-portal' then
        portalCalls = portalCalls + 1
      elseif command == 'monarch-toggle-wifi off' and failRadio then
        callback({exitCode = 1, stderr = 'radio failed'})
      elseif command == 'monarch-network-status --verbose' then
        callback({exitCode = 0, stdout = activeStatus})
      elseif command == 'monarch-network-interfaces' then
        callback({exitCode = 0, stdout = interfaceRecords})
      elseif callback then
        callback({exitCode = 0, stdout = {}})
      end
    end,
  },
}, {__index = _G})
assert(load(source, 'network panel fixture', 't', environment))()

local function hasText(text, node)
  node = node or rendered
  if node.properties.text == text then return true end
  for _, child in ipairs(node.children or {}) do
    if hasText(text, child) then return true end
  end
  return false
end
local function tickScan()
  for _ = 1, 10 do environment.update() end
  return assert(table.remove(scanCallbacks, 1), 'automatic rescan must start')
end

environment.onOpen()
tickScan()({exitCode = 1, stderr = 'scan failed'})
assert(hasText('scan failed'), 'failed automatic rescan must show its error')
tickScan()({exitCode = 0, stdout = {}})
assert(not hasText('scan failed'), 'successful automatic retry must clear the scan error')
print('ok - automatic rescan recovery clears its displayed failure')

failRadio = true
environment.onRadioChanged(false)
assert(hasText('radio failed'), 'action failure must be displayed')
tickScan()({exitCode = 0, stdout = {}})
assert(hasText('radio failed'), 'successful scans must preserve unrelated action errors')
tickScan()({exitCode = 1, stderr = 'scan failed'})
assert(hasText('radio failed'), 'scan failure must not overwrite action errors')
tickScan()({exitCode = 0, stdout = {}})
assert(hasText('radio failed') and not hasText('scan failed'), 'recovery must clear only scan-owned errors')
print('ok - scan failures and recovery preserve unrelated action errors')

environment.onRescanClicked()
assert(hasText('radio failed'), 'manual rescan must not clear an unrelated action error')
assert(table.remove(scanCallbacks, 1))({exitCode = 0, stdout = {}})
assert(hasText('radio failed'), 'manual retry must preserve unrelated action errors')
print('ok - manual rescan preserves unrelated action errors too')

activeStatus = {iface = 'eth0', type = 'ethernet', internet_ping_ms = '8', rx_bytes = '4096', tx_bytes = '2048'}
interfaceRecords = {{iface = 'eth0', type = 'ethernet', connected = true, managed = true,
  virtual = false, routable = true, uuid = 'wired', metrics = {-1, -1},
  addresses = {{family = 'inet6', address = '2001:db8::50', prefix = 64, scope = 'global'}}, gateways = {}}}
environment.onOpen('details')
assert(hasText('Active Internet output'), 'IPv6 status must mark the Internet output as active')
assert(hasText('2001:db8::50/64'), 'IPv6 details must retain the active address')
assert(hasText('INTERNET LINK · eth0') and hasText('8.0 ms'), 'IPv6 status must retain active link statistics')
environment.onOpen()
assert(hasText('Currently using: eth0'), 'primary view must identify the IPv6 Internet output')
print('ok - IPv6 status drives active markers and statistics in both panel views')

local function button(text, node)
  node = node or rendered
  if node.kind == 'button' and node.properties.text == text then return node.properties end
  for _, child in ipairs(node.children or {}) do
    local found = button(text, child)
    if found then return found end
  end
end

activeStatus.connectivity = 'limited'
environment.onOpen()
local retry = assert(button('Check again'), 'limited connectivity must offer a recheck')
assert(not button('Sign in'), 'limited connectivity is not evidence of a captive portal')
environment[retry.onClick]()
environment[retry.onClick]()
assert(checkCalls == 1 and checkCallback, 'recheck must issue exactly one connectivity probe')
assert(button('Checking…').enabled == false, 'in-flight recheck must show progress and disable duplicate clicks')
activeStatus.connectivity = 'full'
checkCallback({exitCode = 0})
assert(not button('Check again') and not button('Sign in'), 'full connectivity must clear the warning')
assert(portalCalls == 0, 'recheck must not open a browser')
print('ok - limited connectivity retries the probe without captive sign-in or duplicate requests')

activeStatus.connectivity = 'limited'
environment.onOpen()
environment[assert(button('Check again')).onClick]()
checkCallback({exitCode = 1, stderr = 'check failed'})
assert(hasText('check failed') and button('Check again'), 'probe failures must retain a usable retry action')
activeStatus.connectivity = 'portal'
environment.onOpen()
environment[assert(button('Sign in')).onClick]()
assert(portalCalls == 1 and not button('Check again'), 'only a detected portal should offer browser sign-in')
activeStatus.connectivity = 'full'
environment.onOpen()
environment.onPortalClicked()
environment.onConnectivityCheckClicked()
assert(portalCalls == 1 and checkCalls == 2, 'stale banner callbacks must not launch actions after recovery')
print('ok - failed checks remain retryable and captive sign-in is restricted to portal state')
