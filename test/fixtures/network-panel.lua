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
local ethernetCalls = 0
local now, wifiRows, joins, requests, writes = 1000, {}, {}, {}, {}
local monitor
local radioEnabled = true
local shared = {
  trim = function(value) return value:match('^%s*(.-)%s*$') end,
  bin = function(name) return name end,
  parseKeyValue = function(value)
    local copy = {}
    for key, item in pairs(value) do copy[key] = item end
    return copy
  end,
  parseNetworks = function(value) return value end,
  sortNetworks = function(value) return value end,
  signalGlyph = function() return 'wifi' end,
  bandLabel = function(value) return value end,
  errorFrom = function(result, fallback) return result.stderr or fallback end,
  shellQuote = function(value) return "'" .. value .. "'" end,
  isEnterprise = function(network) return network.security == '802.1X' end,
  isSecured = function(network) return network.security ~= 'open' end,
  requiresCredentials = function(network) return network.security ~= 'open' and network.security ~= 'OWE' end,
}
local ui = setmetatable({}, {__index = function(_, kind)
  return function(properties, children) return {kind = kind, properties = properties, children = children} end
end})
local environment = setmetatable({
  require = function() return shared end,
  ui = ui,
  panel = {render = function(tree) rendered = tree end, setWantsSecondTicks = function() end},
  noctalia = {
    nowMs = function() return now end,
    fileExists = function() return false end,
    json = {decode = function(value) return value end, encode = function(value) return value end},
    writeFile = function(path, request) writes[path] = request; table.insert(requests, request); return true end,
    runStream = function(_, callback) monitor = callback end,
    runAsync = function(command, callback)
      if command == 'monarch-wifi-panel list --rescan' then
        scanCallbacks[#scanCallbacks + 1] = function(result)
          if result.exitCode == 0 then result.stdout = {enabled = true, present = true, networks = wifiRows} end
          callback(result)
        end
      elseif command == 'monarch-wifi-panel list' then
        callback({exitCode = 0, stdout = {enabled = radioEnabled, present = true, networks = wifiRows}})
      elseif command == 'monarch-wifi-panel prepare' then
        callback({exitCode = 0, stdout = '/private/monarch-wifi-fixture'})
      elseif command:find('monarch-wifi-panel join', 1, true) then
        table.insert(joins, callback)
      elseif command == 'LC_ALL=C /usr/bin/nmcli networking connectivity check' then
        checkCalls = checkCalls + 1
        checkCallback = callback
      elseif command == 'monarch-network-captive-portal' then
        portalCalls = portalCalls + 1
      elseif command:find('monarch-network-ethernet', 1, true) then
        ethernetCalls = ethernetCalls + 1
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
now = now + 3001
environment.update()
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
now = now + 3001
environment.update()
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

interfaceRecords = {{iface = 'eth0', type = 'ethernet', connected = false, connecting = true,
  state = 'connecting (getting IP configuration)', managed = true, virtual = false,
  routable = false, uuid = '', metrics = {}, addresses = {}, gateways = {}}}
environment.onOpen()
assert(hasText('Connecting…'), 'compound activation state must be displayed as connecting')
assert(assert(button('Connect')).enabled == false, 'connecting interface must disable duplicate activation')
button('Connect').onClick()
assert(ethernetCalls == 0, 'connecting interface callbacks must not invoke activation')
print('ok - compound connecting states display progress and disable Ethernet activation')

local function input(key, node)
  node = node or rendered
  if node.kind == 'input' and node.properties.key == key then return node.properties end
  for _, child in ipairs(node.children or {}) do
    local found = input(key, child)
    if found then return found end
  end
end
activeStatus, interfaceRecords = {}, {}
wifiRows = {{key = 'wifi-key', ssid = 'Fixture', uuid = 'saved-uuid', device = 'wlan0', bssid = 'ap',
  saved = true, connected = false, signal = 80, security = 'WPA3'}}
environment.onOpen()
button('Connect').onClick()
assert(#requests == 1 and requests[1].password == '')
joins[1]({exitCode = 1, stderr = 'Secrets were required, but not provided'})
button('Connect').onClick()
assert(input('password'), 'a saved profile must allow credential repair after failure')
input('password').onChange("not-a-real-secret ' ; $()")
input('password').onSubmit("not-a-real-secret ' ; $()")
assert(requests[2].uuid == 'saved-uuid' and requests[2].password == "not-a-real-secret ' ; $()")
assert(not button('Connect').enabled)
environment.onClose()
environment.onOpen()
assert(not button('Connect').enabled, 'reopening must retain the action lock')
button('Connect').onClick()
assert(#joins == 2, 'no concurrent join may start after reopening')
joins[2]({exitCode = 0})
assert(button('Connect').enabled)
assert(not input('password'))
print('ok - saved credentials can be repaired privately without forgetting or overlapping activation')

radioEnabled = false
environment.onOpen()
assert(hasText('Wi-Fi is off'))
radioEnabled = true
monitor()
environment.update()
assert(button('Connect'), 'external events must refresh the network list')
assert(not hasText('Wi-Fi is off'), 'external radio enable must be reflected without reopening')
print('ok - NetworkManager events trigger a cache refresh')

wifiRows = {{key = 'new-key', ssid = 'New network', uuid = '', device = 'wlan0', bssid = 'ap',
  saved = false, connected = false, signal = 80, security = 'WPA3'}}
environment.onClose()
environment.onOpen()
button('Connect').onClick()
input('password').onChange('incorrect-fixture')
input('password').onSubmit('incorrect-fixture')
assert(requests[3].uuid == '')
wifiRows = {{key = 'new-key', ssid = 'New network', uuid = 'created-uuid', device = 'wlan0', bssid = 'new-ap',
  saved = true, connected = false, signal = 40, security = 'WPA3'}}
joins[3]({exitCode = 1, stderr = 'Authentication failed'})
input('password').onChange('corrected-fixture')
input('password').onSubmit('corrected-fixture')
assert(requests[4].uuid == 'created-uuid', 'retry must repair the profile retained after the first failure')
assert(requests[4].bssid == 'new-ap', 'the frozen form must use the current access point')
joins[4]({exitCode = 0})
print('ok - a failed first join refreshes the retained profile identity before credential repair')
