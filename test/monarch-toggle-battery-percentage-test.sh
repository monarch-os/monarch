#!/bin/bash

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export PATH="$TMP_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TMP_ROOT/bin"

cat >"$TMP_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOCTALIA_CALLS"
EOF
chmod +x "$TMP_ROOT/bin/noctalia"
export NOCTALIA_CALLS="$TMP_ROOT/noctalia-calls"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

grep -Fx '[widget.battery.actions]' "$ROOT/config/noctalia/config.toml" >/dev/null || fail "battery actions are configured"
grep -Fx 'right = "exec monarch-toggle-battery-percentage"' "$ROOT/config/noctalia/config.toml" >/dev/null || fail "right click toggles the battery percentage"
pass "right click toggles the battery percentage"

enabled=$("$ROOT/bin/monarch-toggle-battery-percentage" status | jq -r .enabled)
[[ $enabled == false ]] || fail "percentage starts hidden"
pass "percentage starts hidden"

"$ROOT/bin/monarch-toggle-battery-percentage" on
grep -qx 'show_label = true' "$HOME/.config/noctalia/monarch-battery-percentage.toml" || fail "on writes the Noctalia override"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg config-reload' || fail "on reloads Noctalia"
pass "on writes the override and reloads Noctalia"

"$ROOT/bin/monarch-toggle-battery-percentage" toggle
[[ ! -f $HOME/.config/noctalia/monarch-battery-percentage.toml ]] || fail "toggle removes the override"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg config-reload' || fail "toggle reloads Noctalia"
pass "toggle removes the override and reloads Noctalia"

"$ROOT/bin/monarch-toggle-battery-percentage" off
[[ ! -e $HOME/.config/noctalia/monarch-battery-percentage.toml.tmp ]] || fail "off removes temporary state"
pass "off remains idempotent"
