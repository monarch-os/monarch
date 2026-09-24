#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

launch_or_focus="$ROOT/bin/monarch-launch-or-focus"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin"

cat >"$sandbox/bin/niri" <<'STUB'
#!/bin/bash
printf '[]\n'
STUB

cat >"$sandbox/bin/setsid" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@"
STUB

cat >"$sandbox/bin/monarch-launch-or-focus" <<'STUB'
#!/bin/bash
exec "$LAUNCH_OR_FOCUS" "$@"
STUB

chmod +x "$sandbox/bin/niri" "$sandbox/bin/setsid" "$sandbox/bin/monarch-launch-or-focus"
export LAUNCH_OR_FOCUS="$launch_or_focus"

run_launch() {
  PATH="$sandbox/bin:$PATH" "$launch_or_focus" pattern "$@"
}

actual=$(run_launch -- app --flag "two words")
expected=$'<app>\n<--flag>\n<two words>'
[[ $actual == "$expected" ]] || fail "launch-or-focus preserves direct argument boundaries" "expected:\n$expected\nactual:\n$actual"
pass "launch-or-focus preserves direct argument boundaries"

actual=$(run_launch "app --flag 'two words'")
[[ $actual == "$expected" ]] || fail "launch-or-focus safely parses its legacy command string" "expected:\n$expected\nactual:\n$actual"
pass "launch-or-focus safely parses its legacy command string"

actual=$(PATH="$sandbox/bin:$PATH" "$ROOT/bin/monarch-launch-or-focus-tui" "zsh -c 'fastfetch; read -k 1'")
expected=$'<monarch-launch-tui>\n<zsh>\n<-c>\n<fastfetch; read -k 1>'
[[ $actual == "$expected" ]] ||
  fail "launch-or-focus-tui preserves its documented command-string form" "expected:\n$expected\nactual:\n$actual"
pass "launch-or-focus-tui preserves its documented command-string form"

marker="$sandbox/evaluated"
actual=$(run_launch 'app $(touch '"$marker"')')
[[ ! -e $marker ]] || fail "launch-or-focus treats command substitution as literal data"
[[ $actual == $'<app>\n<$(touch>\n<'"$marker"')>' ]] ||
  fail "launch-or-focus passes shell syntax without executing it" "actual:\n$actual"
pass "launch-or-focus never evaluates shell syntax"
