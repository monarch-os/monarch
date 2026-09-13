#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat >"$test_root/bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${TEST_GROUPS:-wheel}"
STUB
cat >"$test_root/bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == -Qq && $2 == ydotool && ${TEST_YDOTOOL:-false} == true ]]
STUB
cat >"$test_root/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$test_root/bin/gpasswd" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_GPASSWD_CALLS"
STUB
cat >"$test_root/bin/monarch-state" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_STATE_CALLS"
STUB
chmod +x "$test_root/bin/"*

calls="$test_root/gpasswd"
state="$test_root/state"
migration="$ROOT/install/reconcile/schema/1-to-2/input-group.sh"

run_migration() {
  rm -f "$calls" "$state"
  TEST_GROUPS="$1" TEST_YDOTOOL="${2:-false}" USER=tester \
    TEST_GPASSWD_CALLS="$calls" TEST_STATE_CALLS="$state" \
    PATH="$test_root/bin:$PATH" bash "$migration" >/dev/null
}

run_migration "wheel input"
grep -qxF -- '-d tester input' "$calls" || fail "migration did not revoke input"
grep -qxF 'set reboot-required' "$state" || fail "migration did not flag the session change"
pass "migration revokes the historical input-group default"

run_migration wheel
[[ ! -e $calls && ! -e $state ]] || fail "migration changed an already-safe account"
pass "migration is idempotent without input membership"

run_migration "wheel input" true
[[ ! -e $calls && ! -e $state ]] || fail "migration revoked ydotool access"
pass "migration preserves the explicit ydotool opt-in"

if rg -n 'usermod .*input|input.*usermod' \
  "$ROOT/bin/monarch-install-gaming-xbox-controllers" \
  "$ROOT/bin/monarch-remove-gaming-xbox-controllers" >/dev/null; then
  fail "Xbox lifecycle still mutates the input group"
fi
grep -qF 'bash "$transition/input-group.sh"' \
  "$ROOT/install/reconcile/schema/1-to-2/user.sh" ||
  fail "input cleanup is outside the v4-to-v5 transition"
pass "Xbox relies on seat ACLs and the schema transition owns cleanup"
