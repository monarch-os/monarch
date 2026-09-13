#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

cat >"$TEST_ROOT/bin/monarch-file-select" <<EOF
#!/bin/bash
printf '%s\n' '$TEST_ROOT/one file.txt' '$TEST_ROOT/two.txt'
EOF
cat >"$TEST_ROOT/bin/tailscale" <<EOF
#!/bin/bash
printf '%s\0' "\$@" >'$TEST_ROOT/tailscale-call'
[[ \${TAILSCALE_FAIL:-0} == 0 ]]
EOF
cat >"$TEST_ROOT/bin/monarch-notification-send" <<EOF
#!/bin/bash
printf '%s\0' "\$@" >'$TEST_ROOT/notification'
EOF
chmod +x "$TEST_ROOT/bin/"*

PATH="$TEST_ROOT/bin:$PATH" "$ROOT/bin/monarch-tailscale-send" phone
grep -Fzq "$TEST_ROOT/one file.txt" "$TEST_ROOT/tailscale-call" || fail "send loses spaced paths"
grep -Fzq 'phone:' "$TEST_ROOT/tailscale-call" || fail "send loses its target"
grep -Fzq '2 files' "$TEST_ROOT/notification" || fail "send does not announce the transfer"
pass "send uses the picker and preserves file arguments"

if PATH="$TEST_ROOT/bin:$PATH" TAILSCALE_FAIL=1 "$ROOT/bin/monarch-tailscale-send" phone "$TEST_ROOT/two.txt"; then
  fail "send ignores transfer failure"
fi
grep -Fzq 'Could not send to phone' "$TEST_ROOT/notification" || fail "send failure is not announced"
pass "send reports transfer failure"
