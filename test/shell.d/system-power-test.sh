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
monarch-state clear re*-required
monarch-niri-window-close-all
sleep 1
EOF

  diff -u "$expected_log" "$call_log" ||
    fail "$action runs after being scheduled outside the terminal scope"
  pass "$action runs after being scheduled outside the terminal scope"
}

run_power_command reboot
assert_power_calls reboot reboot

state_dir="$HOME/.local/state/monarch"
mkdir -p "$state_dir"
touch "$state_dir/reboot-required" "$state_dir/restart-test-required"
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
pass "reboot leaves state and windows alone when scheduling fails"
