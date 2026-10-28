#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
lua - "$ROOT" <<'LUA'
local root = arg[1]
local visible, tooltip, text, interval
local reply = {exitCode = 0, stdout = "off\n"}
local calls = {}
local command = "/usr/share/monarch/bin/monarch-toggle-notification-silencing"
noctalia = {
  setUpdateInterval = function(ms) interval = ms end,
  runAsync = function(argv, callback)
    table.insert(calls, argv)
    if argv == command then
      reply = {exitCode = 0, stdout = "off\n"}
      callback({exitCode = 0})
    else
      assert(argv == "/usr/bin/noctalia msg notification-dnd-status")
      callback(reply)
    end
  end,
}
barWidget = {
  setVisible = function(value) visible = value end,
  setText = function(value) text = value end,
  setColor = function(value) assert(value == "primary") end,
  setTooltip = function(value) tooltip = value end,
  clearTooltip = function() tooltip = nil end,
}
require = function(path)
  assert(path == "./indicator.luau")
  return {bin = function(name)
    assert(name == "monarch-toggle-notification-silencing")
    return command
  end}
end
assert(loadfile(root .. "/default/noctalia/plugins/monarch-indicators/dnd.luau"))()
assert(interval == 2000 and visible == false)
update()
assert(visible == false and tooltip == nil)
-- A native/control-center change bypasses Monarch's toggle command.
reply = {exitCode = 0, stdout = "on\n"}
update()
assert(visible == true and text == "󰂛" and tooltip == "Do not disturb - allow notifications")
reply = {exitCode = 0, stdout = "off\n"}
update()
assert(visible == false and tooltip == nil)
for _, result in ipairs({{exitCode = 1, stdout = "on\n"},
  {exitCode = 0, stdout = ""}, {exitCode = 0, stdout = "unknown\n"},
  {exitCode = 0, stdout = "on\noff\n"}}) do
  reply = result
  update()
  assert(visible == false and tooltip == nil)
end
for _, argv in ipairs(calls) do
  assert(argv == "/usr/bin/noctalia msg notification-dnd-status")
end
reply = {exitCode = 0, stdout = "on\n"}
update()
onClick()
assert(visible == false and tooltip == nil)
assert(calls[#calls - 1] == command)
assert(calls[#calls] == "/usr/bin/noctalia msg notification-dnd-status")
print("PASS: DND reads native on/off and errors without a Bash/JSON status wrapper; clicks requery native state")
LUA
