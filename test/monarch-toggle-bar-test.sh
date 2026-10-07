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
[[ ${NOCTALIA_FAIL:-} != "$*" ]] || exit 1
exit 0
EOF
chmod +x "$TMP_ROOT/bin/noctalia"
export NOCTALIA_CALLS="$TMP_ROOT/noctalia-calls"
export MONARCH_TOGGLE_CALLS="$TMP_ROOT/toggle-calls"
export MONARCH_TEST_ROOT="$ROOT"

cat >"$TMP_ROOT/bin/monarch-toggle" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$MONARCH_TOGGLE_CALLS"
exec "$MONARCH_TEST_ROOT/bin/monarch-toggle" "$@"
EOF
chmod +x "$TMP_ROOT/bin/monarch-toggle"

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
[[ $(wc -l <"$MONARCH_TOGGLE_CALLS") == 1 ]] || fail "off uses the shared toggle"
pass "off hides the bar and records it"

"$ROOT/bin/monarch-toggle-bar" apply
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-hide' || fail "apply restores the hidden state"
[[ $(wc -l <"$MONARCH_TOGGLE_CALLS") == 1 ]] || fail "apply unexpectedly flipped the flag"
pass "apply restores the hidden state"

"$ROOT/bin/monarch-toggle-bar" toggle
[[ ! -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "toggle records the visible state"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-show' || fail "toggle shows the bar"
[[ $(wc -l <"$MONARCH_TOGGLE_CALLS") == 2 ]] || fail "toggle does not use the shared toggle"
pass "toggle shows the bar and records it"

"$ROOT/bin/monarch-toggle-bar" on
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg bar-show' || fail "on is idempotent"
[[ $(wc -l <"$MONARCH_TOGGLE_CALLS") == 2 ]] || fail "on unexpectedly flipped the flag"
pass "on explicitly shows the bar"

if NOCTALIA_FAIL='msg bar-hide' "$ROOT/bin/monarch-toggle-bar" off; then
  fail "off succeeded when Noctalia rejected the change"
fi
[[ ! -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "failed hide changed the flag"
[[ $(wc -l <"$MONARCH_TOGGLE_CALLS") == 2 ]] || fail "failed hide used the shared toggle"
pass "a failed Noctalia command leaves the preference unchanged"
