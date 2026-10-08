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
exit "${NOCTALIA_STATUS:-0}"
EOF

for command in monarch-state monarch-niri-window-close-all sleep; do
  cat >"$mock_bin/$command" <<'EOF'
#!/bin/bash

printf '%s' "$(basename "$0")" >>"$CALL_LOG"
(($# == 0)) || printf ' %s' "$*" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF
done
chmod +x "$mock_bin"/*

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

run_power_command shutdown
expected_log="$test_tmp/shutdown-expected.log"
cat >"$expected_log" <<'EOF'
noctalia msg session shutdown
monarch-state clear re*-required
EOF
diff -u "$expected_log" "$call_log" ||
  fail "shutdown delegates to Noctalia before clearing state"
pass "shutdown delegates to Noctalia without a timer or manual window closure"

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
