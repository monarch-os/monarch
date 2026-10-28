#!/bin/bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/runtime"
cat >"$temporary/bin/noctalia" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
case "$*" in
  'msg plugin '*) exit "${IPC_FAILURE:-0}" ;;
  *) exit "${SETTER_FAILURE:-0}" ;;
esac
SH
chmod 755 "$temporary/bin/noctalia"
export XDG_RUNTIME_DIR="$temporary/runtime" CALL_LOG="$temporary/calls"
export PATH="$temporary/bin:$ROOT/bin:$PATH"

for toggle in idle nightlight; do
  entry=caffeine
  [[ $toggle != "nightlight" ]] || entry=nightlight
  command="$ROOT/bin/monarch-toggle-$toggle"
  marker="$XDG_RUNTIME_DIR/monarch/$entry"
  : >"$CALL_LOG"
  "$command" on
  [[ -f $marker ]] || fail "$entry marker missing"
  [[ $(tail -1 "$CALL_LOG") == "msg plugin monarch/indicators:$entry all refresh" ]] || fail "$entry event precedes state"
  "$command" status | jq -e '.enabled == true' >/dev/null
  "$command" off
  [[ ! -e $marker ]] || fail "$entry marker remains"
  [[ $(tail -1 "$CALL_LOG") == "msg plugin monarch/indicators:$entry all refresh" ]] || fail "$entry removal not signaled"
  IPC_FAILURE=1 "$command" on
  [[ -f $marker ]] || fail "missing widget affects $entry activation"
  IPC_FAILURE=1 "$command" off
  : >"$CALL_LOG"
  SETTER_FAILURE=1 "$command" on && fail "failed $entry setter reports success"
  [[ ! -e $marker ]] || fail "failed setter leaves $entry marker"
  ! grep -q 'msg plugin ' "$CALL_LOG" || fail "failed setter advertises $entry change"
done
pass "toggle events follow successful state changes and absent widgets do not break commands"

monarch-toggle-idle claim update-owner
monarch-toggle-idle on
[[ $(cat "$XDG_RUNTIME_DIR/monarch/caffeine") == user ]] || fail "user ownership not recorded"
: >"$CALL_LOG"
monarch-toggle-idle release update-owner
[[ -f $XDG_RUNTIME_DIR/monarch/caffeine && ! -s $CALL_LOG ]] || fail "stale release changed user choice"
monarch-toggle-idle off
pass "event notifications preserve Caffeine ownership and stale releases"

lua - "$ROOT" <<'LUA'
local root = arg[1]
local path = root .. "/default/noctalia/plugins/monarch-indicators/"
for _, entry in ipairs({"caffeine", "nightlight"}) do
  for _, configured in ipairs({"/run/user/123", "", false}) do
    local present = false
    local seenPath = nil
    local visible, tooltip, interval = nil, nil, nil
    local reads, spawns = 0, 0
    noctalia = {
      getenv = function(name)
        assert(name == "XDG_RUNTIME_DIR")
        if configured == false then return nil end
        return configured
      end,
      readFile = function(file)
        assert(file == "/proc/self/status")
        reads = reads + 1
        return "Name:\tnoctalia\nUid:\t123\t123\t123\t123\n"
      end,
      fileInfo = function(file)
        seenPath = file
        if present then return {isDir = present == "directory"} end
        return nil
      end,
      setUpdateInterval = function(ms) interval = ms end,
      log = function(message) error(message) end,
      runAsync = function(command, callback)
        assert(command:find("monarch-toggle-", 1, true))
        spawns = spawns + 1
        present = false
        callback()
      end,
    }
    barWidget = {
      setVisible = function(value) visible = value end,
      setText = function(text) assert(#text > 0) end,
      setColor = function(color) assert(color == "primary") end,
      setTooltip = function(text) tooltip = text end,
      clearTooltip = function() tooltip = nil end,
    }
    local originalRequire = require
    require = function(module)
      if module == "./indicator.luau" then
        return {bin = function(name) return "/usr/share/monarch/bin/" .. name end}
      end
      assert(module == "./runtime-toggle.luau")
      local moduleEnv = setmetatable({}, {__index = _G})
      return assert(loadfile(path .. "runtime-toggle.luau", "t", moduleEnv))()
    end
    assert(loadfile(path .. entry .. ".luau"))()
    require = originalRequire
    assert(visible == false and tooltip == nil and interval == 30000)
    assert(seenPath == "/run/user/123/monarch/" .. entry)
    present = true
    onIpc("unrelated")
    assert(visible == false)
    onIpc("refresh")
    assert(visible == true and tooltip ~= nil)
    assert(spawns == 0)
    present = false
    update()
    assert(visible == false and tooltip == nil)
    present = true
    update()
    assert(visible == true)
    present = "directory"
    update()
    assert(visible == false)
    present = true
    onClick()
    assert(spawns == 1 and visible == false)
    assert(reads == ((configured == false or configured == "") and 1 or 0))
  end
end
print("PASS: widgets initialize/read native state, handle IPC and catch-up, preserve clicks without polling subprocesses")
LUA
