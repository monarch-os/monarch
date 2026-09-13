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
exit 0
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

enabled=$("$ROOT/bin/monarch-toggle-bar" status | jq -r .enabled)
[[ $enabled == true ]] || fail "bar starts enabled"
pass "bar starts enabled"

"$ROOT/bin/monarch-toggle-bar" off
[[ -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "off records the hidden state"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-hide' || fail "off hides the bar"
pass "off hides the bar and records it"

"$ROOT/bin/monarch-toggle-bar" apply
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-hide' || fail "apply restores the hidden state"
pass "apply restores the hidden state"

"$ROOT/bin/monarch-toggle-bar" toggle
[[ ! -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "toggle records the visible state"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-show' || fail "toggle shows the bar"
pass "toggle shows the bar and records it"

"$ROOT/bin/monarch-toggle-bar" on
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-show' || fail "on is idempotent"
pass "on explicitly shows the bar"
