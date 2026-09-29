#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export TEST_SCREENCAST_DND="$test_tmp"
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/noctalia" <<'EOF'
#!/bin/bash
[[ ! -e $TEST_SCREENCAST_DND/unavailable ]] || exit 1
case $2 in
  notification-dnd-status) cat "$TEST_SCREENCAST_DND/status" ;;
  notification-dnd-set)
    printf '%s\n' "$3" >"$TEST_SCREENCAST_DND/status"
    printf '%s\n' "$3" >>"$TEST_SCREENCAST_DND/calls"
    ;;
esac
EOF

cat >"$test_tmp/bin/niri" <<'EOF'
#!/bin/bash
cat "$TEST_SCREENCAST_DND/casts"
EOF

chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH"
source "$ROOT/bin/monarch-niri-screencast-dnd"

printf '%s\n' off >"$test_tmp/status"
printf '%s\n' '[]' >"$test_tmp/casts"
update_shared
[[ $shared == false && $managed == false && ! -e $test_tmp/calls ]]

printf '%s\n' '[{"kind":"PipeWire","is_active":true}]' >"$test_tmp/casts"
update_shared
[[ $shared == true && $managed == true && $(<"$test_tmp/status") == on ]]

printf '%s\n' '[{"kind":"PipeWire","is_active":false},{"kind":"ExtImageCopyCapture","is_active":true}]' >"$test_tmp/casts"
update_shared
[[ $(<"$test_tmp/calls") == on ]]

printf '%s\n' '[{"kind":"PipeWire","is_active":false}]' >"$test_tmp/casts"
update_shared
[[ $shared == false && $managed == false && $(<"$test_tmp/status") == off ]]
[[ $(<"$test_tmp/calls") == $'on\noff' ]]
pass "DND follows active casts and waits for the last one to stop"

printf '%s\n' on >"$test_tmp/status"
printf '%s\n' '[{"kind":"PipeWire","is_active":true}]' >"$test_tmp/casts"
update_shared
printf '%s\n' off >"$test_tmp/status"
sync_dnd
[[ $managed == false && $(<"$test_tmp/status") == on ]]
printf '%s\n' '[]' >"$test_tmp/casts"
update_shared
[[ $managed == false && $(<"$test_tmp/status") == on ]]
[[ $(<"$test_tmp/calls") == $'on\noff\non' ]]
pass "DND that was already active stays active"

printf '%s\n' off >"$test_tmp/status"
touch "$test_tmp/unavailable"
printf '%s\n' '[{"kind":"PipeWire","is_active":true}]' >"$test_tmp/casts"
update_shared
[[ $shared == true && $managed == false ]]
rm "$test_tmp/unavailable"
sync_dnd
[[ $managed == true && $(<"$test_tmp/status") == on ]]

printf '%s\n' broken >"$test_tmp/casts"
update_shared
[[ $shared == true && $(<"$test_tmp/status") == on ]]
restore_dnd
[[ $managed == false && $(<"$test_tmp/status") == off ]]
pass "DND recovers after Noctalia starts and survives an invalid cast response"

grep -qF 'monarch-screencast-dnd.service' "$ROOT/install/user/first-run/enable-user-units.sh"
grep -qF 'monarch-screencast-dnd.service' "$ROOT/install/reconcile/user.sh"
pass "fresh installs and upgrades enable the watcher"
