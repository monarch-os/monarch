#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
cat >"$temporary/bin/pgrep" <<'SH'
#!/bin/bash
[[ $* == "-u $UID -f ^gpu-screen-recorder" ]] || exit 99
echo must-not-leak
exit "${RECORDER_STATUS:-1}"
SH
chmod 755 "$temporary/bin/pgrep"
for status in 0 1; do
  result=0
  output=$(RECORDER_STATUS="$status" PATH="$temporary/bin:/usr/bin:/bin" HOME="$temporary/missing-home" \
    MONARCH_SCREENRECORD_DIR="$temporary/missing-videos" "$ROOT/bin/monarch-capture-screenrecording" --status) || result=$?
  (( result == status )) && [[ -z $output && ! -e $temporary/missing-home && ! -e $temporary/missing-videos ]] || exit 1
done
echo 'PASS: status is silent, read-only and independent of output directories/session setup'

lua - "$ROOT" <<'LUA'
local root = arg[1]
local calls, pending = {}, {}
local visible, tooltip, interval
local accept = true
local command = "/usr/share/monarch/bin/monarch-capture-screenrecording"
noctalia = {
  setUpdateInterval = function(value) interval = value end,
  runAsync = function(value, callback)
    table.insert(calls, value)
    assert(value == command or value == command .. " --status")
    if accept then table.insert(pending, callback) end
    return accept
  end,
}
barWidget = {
  setVisible = function(value) visible = value end,
  setText = function(value) assert(value == "󰻂") end,
  setColor = function(value) assert(value == "error") end,
  setTooltip = function(value) tooltip = value end,
  clearTooltip = function() tooltip = nil end,
}
require = function(path)
  assert(path == "./indicator.luau")
  return {bin = function(name) assert(name == "monarch-capture-screenrecording"); return command end}
end
local function finish(status)
  local callback = table.remove(pending, 1)
  assert(callback)
  callback({exitCode = status})
end
local function load()
  assert(loadfile(root .. "/default/noctalia/plugins/monarch-indicators/screen-recording.luau"))()
end
load()
assert(interval == 30000 and visible == false and #pending == 1)
finish(0)
assert(visible and tooltip == "Stop recording")
onIpc("unrelated")
assert(#pending == 0)
onIpc("refresh")
onIpc("refresh")
assert(#pending == 1)
finish(0)
assert(#pending == 1) -- An event during a query cannot be lost.
finish(1)
assert(not visible and tooltip == nil)
update() -- External capture discovered by the catch-up timer.
finish(0)
assert(visible)
update() -- Crash/external stop clears the old state.
finish(1)
assert(not visible)
accept = false
update()
assert(#pending == 0)
accept = true
update()
finish(0)
assert(visible)
load() -- Shell reload queries an already-running recording.
finish(0)
assert(visible)
onClick()
assert(calls[#calls] == command)
finish(0)
assert(calls[#calls] == command .. " --status")
finish(1)
assert(not visible and tooltip == nil)
print('PASS: initial state, IPC, coalesced refreshes, 30s fallback, crash/reload recovery and clicks')
LUA
