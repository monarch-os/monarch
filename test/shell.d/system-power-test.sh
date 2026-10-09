#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/systemd-run" <<'EOF'
#!/bin/bash

printf 'systemd-run %s\n' "$*" >>"$CALL_LOG"
[[ ${FAIL_SYSTEMD_RUN:-false} == "true" ]] && exit 1
exit 0
EOF

cat >"$mock_bin/noctalia" <<'EOF'
#!/bin/bash

printf 'noctalia %s\n' "$*" >>"$CALL_LOG"
printf 'ok\n'
exit "${NOCTALIA_STATUS:-0}"
EOF

for command in monarch-niri-window-close-all sleep; do
  cat >"$mock_bin/$command" <<'EOF'
#!/bin/bash

printf '%s' "$(basename "$0")" >>"$CALL_LOG"
(($# == 0)) || printf ' %s' "$*" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF
done
cat >"$mock_bin/monarch-state" <<'EOF'
#!/bin/bash

printf 'monarch-state %s\n' "$*" >>"$CALL_LOG"
exec "$ROOT/bin/monarch-state" "$@"
EOF
chmod +x "$mock_bin"/*
export HOME="$test_tmp/home"

run_power_command() {
  local action="$1"

  : >"$call_log"
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/monarch-system-$action"
}

assert_power_calls() {
  local action="$1"
  local systemctl_action="$2"
  local expected_log="$test_tmp/$action-expected.log"

  cat >"$expected_log" <<EOF
systemd-run --user --collect --quiet --on-active=2s systemctl $systemctl_action --no-wall
monarch-niri-window-close-all
sleep 1
EOF

  diff -u "$expected_log" "$call_log" ||
    fail "$action runs after being scheduled outside the terminal scope"
  pass "$action runs after being scheduled outside the terminal scope"
}

state_dir="$HOME/.local/state/monarch"
mkdir -p "$state_dir"
touch "$state_dir/reboot-required" "$state_dir/restart-test-required"
run_power_command reboot
[[ -f $state_dir/reboot-required && -f $state_dir/restart-test-required ]] ||
  fail "scheduling a reboot removed restart markers before a boot change"
assert_power_calls reboot reboot
pass "scheduled reboot preserves restart markers until an actual boot change"

run_power_command shutdown >"$test_tmp/shutdown-output"
[[ $(cat "$test_tmp/shutdown-output") == "ok" ]] || fail "Noctalia did not acknowledge the request"
expected_log="$test_tmp/shutdown-expected.log"
cat >"$expected_log" <<'EOF'
noctalia msg session shutdown
EOF
diff -u "$expected_log" "$call_log" ||
  fail "IPC acceptance must not clear state or close windows before asynchronous shutdown"
[[ -f $state_dir/reboot-required && -f $state_dir/restart-test-required ]] ||
  fail "IPC acceptance removed restart markers without a committed shutdown"
pass "shutdown delegates to Noctalia and preserves state after IPC acceptance"

for status in 1 127; do
  : >"$call_log"
  actual_status=0
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" NOCTALIA_STATUS="$status" \
    "$ROOT/bin/monarch-system-shutdown" || actual_status=$?
  (( actual_status == status )) || fail "shutdown propagates IPC error $status"
  [[ $(cat "$call_log") == "noctalia msg session shutdown" ]] ||
    fail "shutdown leaves state and windows alone after IPC error $status"
  pass "shutdown preserves state and propagates IPC error $status"
done

: >"$call_log"
if PATH="$mock_bin:$PATH" CALL_LOG="$call_log" FAIL_SYSTEMD_RUN=true \
  "$ROOT/bin/monarch-system-reboot"; then
  fail "reboot aborts when scheduling fails"
fi

if (( $(wc -l <"$call_log") != 1 )); then
  fail "reboot leaves state and windows alone when scheduling fails"
fi
[[ -f $state_dir/reboot-required && -f $state_dir/restart-test-required ]] ||
  fail "failed reboot scheduling removed restart markers"
pass "reboot leaves state and windows alone when scheduling fails"

state_command="$test_tmp/monarch-state"
sed "s|/proc/sys/kernel/random/boot_id|$test_tmp/boot-id|g" "$ROOT/bin/monarch-state" >"$state_command"
boot_one=11111111-1111-1111-1111-111111111111
boot_two=22222222-2222-2222-2222-222222222222
printf '%s\n' "$boot_one" >"$test_tmp/boot-id"
bash "$state_command" set reboot-required
bash "$state_command" set restart-test-required
[[ $(cat "$state_dir/reboot-required") == "$boot_one" ]] || fail "restart marker lacks boot identity"
touch -d @1000000000 "$state_dir/reboot-required"
touch -d @2100000000 "$state_dir/restart-test-required"
bash "$state_command" clear-stale-restarts
[[ -f $state_dir/reboot-required && -f $state_dir/restart-test-required ]] ||
  fail "clock corrections invalidate current restart markers"
bash "$state_command" clear-stale-restarts
[[ -f $state_dir/reboot-required ]] || fail "same-boot shell restart clears current restart markers"
pass "restart markers survive same-boot starts regardless of wall-clock timestamps"

touch "$state_dir/logout-required"
: >"$state_dir/restart-legacy-required"
bash "$state_command" clear-stale-restarts
[[ $(cat "$state_dir/restart-legacy-required") == "$boot_one" ]] ||
  fail "legacy marker is not conservatively associated with the current boot"
pass "legacy empty markers are retained until a known boot change"

printf '%s\n' "$boot_two" >"$test_tmp/boot-id"
bash "$state_command" set restart-current-required
bash "$state_command" clear-stale-restarts
[[ ! -e $state_dir/reboot-required && ! -e $state_dir/restart-test-required && ! -e $state_dir/restart-legacy-required ]] ||
  fail "the next boot does not clear the previous boot's restart markers"
[[ -f $state_dir/restart-current-required && -f $state_dir/logout-required ]] ||
  fail "boot cleanup removed a current marker or unrelated state"
pass "restart markers persist in the same boot and expire on the next boot"

printf 'unrecognized\n' >"$state_dir/restart-custom-required"
bash "$state_command" clear-stale-restarts
[[ $(cat "$state_dir/restart-custom-required") == "unrecognized" ]] ||
  fail "boot cleanup modified an unrecognized marker"

: >"$test_tmp/boot-id"
if bash "$state_command" clear-stale-restarts >"$test_tmp/boot-output" 2>&1; then
  fail "missing boot identity reports successful cleanup"
fi
[[ -f $state_dir/restart-current-required ]] || fail "missing boot identity deletes restart markers"
pass "boot cleanup preserves state when boot identity is unavailable"

cat >"$mock_bin/monarch-state" <<'EOF'
#!/bin/bash
printf 'monarch-state %s\n' "$*" >>"$CALL_LOG"
exit 42
EOF
: >"$call_log"
status=0
PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/monarch-update-restart" >"$test_tmp/restart-output" || status=$?
(( status == 42 )) || fail "update continues when stale-marker cleanup fails"
[[ $(cat "$call_log") == "monarch-state clear-stale-restarts" && ! -s $test_tmp/restart-output ]] ||
  fail "update reads restart requirements before clearing obsolete markers"
pass "update clears obsolete markers before inspecting restart requirements"

cat >"$mock_bin/monarch-state" <<'EOF'
#!/bin/bash
exec bash "$TEST_STATE_COMMAND" "$@"
EOF
cat >"$mock_bin/gum" <<'EOF'
#!/bin/bash
printf 'gum %s\n' "$*" >>"$CALL_LOG"
exit 1
EOF
printf '#!/bin/bash\nexit 0\n' >"$mock_bin/pacman"
printf '#!/bin/bash\nexit 1\n' >"$mock_bin/pgrep"
cat >"$mock_bin/monarch-restart-test" <<'EOF'
#!/bin/bash
printf 'restart test\n' >>"$CALL_LOG"
EOF
chmod +x "$mock_bin/"*
consumer_home="$test_tmp/consumer"
mkdir -p "$consumer_home/.local/state/monarch"
printf '%s\n' "$boot_one" >"$consumer_home/.local/state/monarch/reboot-required"
printf '%s\n' "$boot_one" >"$consumer_home/.local/state/monarch/restart-test-required"
printf '%s\n' "$boot_two" >"$test_tmp/boot-id"
: >"$call_log"
HOME="$consumer_home" PATH="$mock_bin:$PATH" CALL_LOG="$call_log" TEST_STATE_COMMAND="$state_command" \
  "$ROOT/bin/monarch-update-restart" >"$test_tmp/restart-output"
[[ ! -e $consumer_home/.local/state/monarch/reboot-required && ! -e $consumer_home/.local/state/monarch/restart-test-required ]] ||
  fail "update retains requirements from a completed power cycle"
! grep -qE 'Updates require reboot|restart test' "$call_log" ||
  fail "update prompts or restarts a service because of obsolete markers"
pass "update removes previous-boot markers without a redundant reboot prompt or service restart"

session_home="$test_tmp/session"
session_state="$session_home/.local/state/monarch"
mkdir -p "$session_state"
printf '%s\n' "$boot_one" >"$session_state/reboot-required"
printf '%s\n' "$boot_one" >"$session_state/restart-test-required"
printf '%s\n' "$boot_two" >"$session_state/restart-current-required"
touch "$session_state/logout-required"

run_session_start() {
  HOME="$session_home" PATH="$mock_bin:$PATH" TEST_STATE_COMMAND="$state_command" CALL_LOG="$call_log" \
    "$ROOT/bin/monarch-hook" post-boot "$@"
}

run_session_start
[[ ! -e $session_state/reboot-required && ! -e $session_state/restart-test-required ]] ||
  fail "session startup retains restart requirements from a previous boot"
[[ -f $session_state/restart-current-required && -f $session_state/logout-required ]] ||
  fail "session startup removes current requirements or unrelated state"
pass "session startup clears old restart markers without requiring user hooks"

HOME="$session_home" bash "$state_command" set reboot-required
run_session_start
[[ -f $session_state/reboot-required && -f $session_state/restart-current-required ]] ||
  fail "a same-boot login removes current restart requirements"
pass "logging in again during the same boot preserves restart requirements"

printf '%s\n' "$boot_one" >"$test_tmp/boot-id"
run_session_start
[[ ! -e $session_state/reboot-required && ! -e $session_state/restart-current-required ]] ||
  fail "logging in after a new boot retains obsolete restart requirements"
pass "logging in after a boot change removes the previous boot's requirements"

mkdir -p "$session_home/.config/monarch/hooks/post-boot.d"
cat >"$session_home/.config/monarch/hooks/post-boot" <<'EOF'
#!/bin/bash
printf 'personal %s\n' "$*" >>"$CALL_LOG"
EOF
cat >"$session_home/.config/monarch/hooks/post-boot.d/personal" <<'EOF'
#!/bin/bash
printf 'fragment %s\n' "$*" >>"$CALL_LOG"
EOF
cat >"$mock_bin/monarch-state" <<'EOF'
#!/bin/bash
printf 'monarch-state %s\n' "$*" >>"$CALL_LOG"
exec bash "$TEST_STATE_COMMAND" "$@"
EOF
: >"$call_log"
run_session_start 'argument with spaces'
[[ $(cat "$call_log") == $'monarch-state clear-stale-restarts\npersonal argument with spaces\nfragment argument with spaces' ]] ||
  fail "session cleanup changes personal hooks, arguments or execution order"
pass "session cleanup runs before personal hooks and preserves their arguments"

printf '%s\n' "$boot_two" >"$session_state/reboot-required"
: >"$call_log"
HOME="$session_home" PATH="$mock_bin:$PATH" TEST_STATE_COMMAND="$state_command" CALL_LOG="$call_log" \
  "$ROOT/bin/monarch-hook" post-update
[[ -f $session_state/reboot-required && ! -s $call_log ]] ||
  fail "an unrelated hook unexpectedly clears restart markers"
pass "other hooks leave restart requirements untouched"

: >"$test_tmp/boot-id"
: >"$call_log"
run_session_start 'argument with spaces' >"$test_tmp/session-output" 2>&1
[[ -f $session_state/reboot-required ]] || fail "failed session cleanup deletes restart requirements"
grep -q 'cleanup failed' "$test_tmp/session-output" || fail "failed session cleanup is not reported"
[[ $(cat "$call_log") == $'monarch-state clear-stale-restarts\npersonal argument with spaces\nfragment argument with spaces' ]] ||
  fail "failed session cleanup prevents personal startup hooks"
pass "failed cleanup retains markers and still runs personal startup hooks"
