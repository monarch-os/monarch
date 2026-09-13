#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$TMP_ROOT/bin:$PATH"
export NOCTALIA_CALLS="$TMP_ROOT/noctalia-calls"
mkdir -p "$HOME/.config/noctalia" "$TMP_ROOT/bin"

cat >"$TMP_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOCTALIA_CALLS"
EOF
chmod +x "$TMP_ROOT/bin/noctalia"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

assert_equals() {
  local message=$1 actual=$2 expected=$3
  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
  pass "$message"
}

assert_equals "missing config defaults to top" \
  "$("$ROOT/bin/monarch-bar-position")" "top"

cat >"$HOME/.config/noctalia/config.toml" <<'EOF'
[bar]
order = ["default"]

[bar.default]
position = "left"
capsule = false
EOF

assert_equals "reads the base bar position" \
  "$("$ROOT/bin/monarch-bar-position")" "left"

"$ROOT/bin/monarch-bar-position" bottom
assert_equals "the override becomes authoritative" \
  "$("$ROOT/bin/monarch-bar-position")" "bottom"
grep -qx 'position = "bottom"' "$HOME/.config/noctalia/zz-monarch-bar-position.toml" || fail "writes the position override"
tail -1 "$NOCTALIA_CALLS" | grep -qx 'msg config-reload' || fail "reloads Noctalia"
pass "writes atomically and reloads Noctalia"

before=$(cat "$HOME/.config/noctalia/config.toml")
"$ROOT/bin/monarch-bar-position" right
assert_equals "changing position preserves the base config" \
  "$(cat "$HOME/.config/noctalia/config.toml")" "$before"
assert_equals "right persists in the override" \
  "$("$ROOT/bin/monarch-bar-position")" "right"

if "$ROOT/bin/monarch-bar-position" diagonal 2>/dev/null; then
  fail "rejects invalid positions"
fi
pass "rejects invalid positions"

[[ ! -e $HOME/.config/noctalia/zz-monarch-bar-position.toml.tmp ]] || fail "leaves no temporary file"
pass "leaves no temporary file"
