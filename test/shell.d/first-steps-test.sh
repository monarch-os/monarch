#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
runtime="$test_tmp/runtime"
mkdir -p "$runtime/bin" "$runtime/install/reconcile"
cp "$ROOT/bin/monarch-setup-first-steps" "$runtime/bin/"
cp "$ROOT/install/reconcile/noctalia-wait.sh" "$runtime/install/reconcile/"
export MONARCH_PATH="$runtime" TEST_FIRST_STEPS="$test_tmp" PATH="$runtime/bin:$PATH"

cat >"$runtime/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_FIRST_STEPS/calls"
if [[ $* == 'msg status' ]]; then
  case ${TEST_FIRST_STEPS_MODE:-ready} in
    network-visit)
      if [[ -f $TEST_FIRST_STEPS/network-open ]]; then
        rm "$TEST_FIRST_STEPS/network-open"
        printf '{"locked":false,"panelOpen":true,"activePanelId":"%s"}\n' "${TEST_FIRST_STEPS_CHILD:-monarch/network:panel}"
      else
        printf '%s\n' '{"locked":false,"panelOpen":false}'
      fi
      ;;
    unavailable) exit 1 ;;
    locked) printf '%s\n' '{"locked":true,"panelOpen":false}' ;;
    busy) printf '%s\n' '{"locked":false,"panelOpen":true}' ;;
    manual)
      monarch-setup-first-steps opened
      printf '%s\n' '{"locked":false,"panelOpen":false}'
      ;;
    *) printf '%s\n' '{"locked":false,"panelOpen":false}' ;;
  esac
elif [[ $* == 'msg panel-open monarch/network:panel' ]]; then
  [[ ${TEST_FIRST_STEPS_NETWORK_LAUNCH:-} != failure ]] || exit 42
  touch "$TEST_FIRST_STEPS/network-open"
elif [[ $1 == "msg" && $2 == "panel-open" ]]; then
  [[ ${TEST_FIRST_STEPS_MODE:-} != rejected ]] || exit 42
  [[ -z ${TEST_FIRST_STEPS_PANEL_DELAY:-} ]] || /usr/bin/sleep "$TEST_FIRST_STEPS_PANEL_DELAY"
  printf '%s\n' "$4" >"$TEST_FIRST_STEPS/context"
  [[ ${TEST_FIRST_STEPS_MODE:-} != unconfirmed ]] || exit 0
  monarch-setup-first-steps opened
  printf 'panel-opened %s\n' "$3" >>"$TEST_FIRST_STEPS/calls"
fi
EOF
cat >"$runtime/bin/sleep" <<'EOF'
#!/bin/bash
[[ ${TEST_FIRST_STEPS_REAL_SLEEP:-} != 1 ]] || exec /usr/bin/sleep "$@"
exit 0
EOF
cat >"$runtime/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
[[ -f $TEST_FIRST_STEPS/installed ]]
EOF
cat >"$runtime/bin/monarch-pkg-aur-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_FIRST_STEPS/installer-args"
printf '%s\n' "$BASHPID" >"$TEST_FIRST_STEPS/installer-pid"
printf '%s\n' "$PPID" >"$TEST_FIRST_STEPS/runner-pid"
touch "$TEST_FIRST_STEPS/installer-started"
while [[ -f $TEST_FIRST_STEPS/block-install ]]; do /usr/bin/sleep 0.02; done
[[ ${TEST_FIRST_STEPS_EXIT:-0} == 0 ]] || exit "$TEST_FIRST_STEPS_EXIT"
touch "$TEST_FIRST_STEPS/installed"
EOF
cat >"$runtime/bin/nm-online" <<'EOF'
#!/bin/bash
[[ ${TEST_FIRST_STEPS_NETWORK:-connected} == connected ]]
EOF
cat >"$runtime/bin/uwsm-app" <<'EOF'
#!/bin/bash
while [[ $1 != -e ]]; do shift; done
shift
printf -v command '%q ' "$@"
printf '%s\n' "$command" >"$TEST_FIRST_STEPS/terminal-command"
case ${TEST_FIRST_STEPS_LAUNCH:-} in
  failure) touch "$TEST_FIRST_STEPS/launcher-failed"; exit 42 ;;
  never) exit 0 ;;
esac
if [[ ${TEST_FIRST_STEPS_LAUNCH:-} == "delayed" ]]; then
  (/usr/bin/sleep 0.2; exec "$@") &
  exit 0
fi
unset MONARCH_PATH XDG_STATE_HOME
exec "$@"
EOF
cat >"$runtime/bin/monarch-update" <<'EOF'
#!/bin/bash
[[ ${TEST_FIRST_STEPS_CONFIRM:-0} == 0 ]] || exit 130
printf '%s\n' "$*" >"$TEST_FIRST_STEPS/update-args"
touch "$TEST_FIRST_STEPS/update-started"
while [[ -f $TEST_FIRST_STEPS/block-update ]]; do /usr/bin/sleep 0.02; done
exit "${TEST_FIRST_STEPS_EXIT:-0}"
EOF
cat >"$runtime/bin/monarch-show-logo" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$runtime/bin/monarch-show-done" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >"$TEST_FIRST_STEPS/update-done"
while [[ -f $TEST_FIRST_STEPS/block-done ]]; do /usr/bin/sleep 0.02; done
EOF
chmod +x "$runtime/bin/"*

fresh_state() {
  export XDG_STATE_HOME="$test_tmp/state-$1"
  state_dir="$XDG_STATE_HOME/monarch/first-steps"
  : >"$test_tmp/calls"
  unset TEST_FIRST_STEPS_MODE
}

fresh_state existing
monarch-setup-first-steps first-login
[[ ! -s $test_tmp/calls ]] || fail "existing users are not offered first steps automatically"
pass "existing users keep manual access without an automatic offer"

fresh_state fresh
monarch-setup-first-steps prepare
[[ -f $state_dir/pending ]] || fail "initial setup arms first steps"
monarch-setup-first-steps first-login
[[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "the panel confirms its first opening"
grep -q '^msg panel-open monarch/first-steps:panel ' "$test_tmp/calls"
jq -e --arg root "$runtime" --arg home "$XDG_STATE_HOME" \
  '.root == $root and .stateHome == $home and .phase == "welcome"' "$test_tmp/context" >/dev/null
cp "$test_tmp/calls" "$test_tmp/expected-calls"
monarch-setup-first-steps first-login
monarch-setup-first-steps prepare
cmp "$test_tmp/calls" "$test_tmp/expected-calls"
[[ ! -e $state_dir/pending ]] || fail "refreshing setup does not rearm an offered guide"
pass "the first session opens the guide exactly once and retains its user state"

monarch-setup-first-steps record appearance
monarch-setup-first-steps open
jq -e '.phase == "appearance"' "$test_tmp/context" >/dev/null
monarch-setup-first-steps reset
jq -e '.phase == "welcome"' "$test_tmp/context" >/dev/null
[[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "manual replay does not rearm startup"
pass "manual access resumes progress and replay preserves the already-shown marker"

for mode in unavailable locked busy rejected unconfirmed; do
  fresh_state "$mode"
  monarch-setup-first-steps prepare
  export TEST_FIRST_STEPS_MODE="$mode"
  if monarch-setup-first-steps first-login >/dev/null 2>&1; then fail "$mode cannot consume the first offer"; fi
  [[ -f $state_dir/pending && ! -e $state_dir/shown ]] || fail "$mode remains pending"
  unset TEST_FIRST_STEPS_MODE
  monarch-setup-first-steps first-login
  [[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "$mode retries when the desktop is ready"
  pass "$mode keeps the guide pending until a confirmed opening"
done

fresh_state concurrent
monarch-setup-first-steps prepare
exec 8>"$state_dir/offer.lock"
flock -n 8
monarch-setup-first-steps first-login
[[ ! -s $test_tmp/calls && -f $state_dir/pending ]] || fail "a concurrent first-login offer is excluded"
flock -u 8
exec 8>&-
monarch-setup-first-steps first-login
pass "concurrent first-login attempts cannot open duplicate guides"

fresh_state manual-race
monarch-setup-first-steps prepare
export TEST_FIRST_STEPS_MODE=manual
monarch-setup-first-steps first-login
[[ -f $state_dir/shown && ! -f $state_dir/pending ]] || fail "manual opening consumes the first offer"
if grep -q '^msg panel-open ' "$test_tmp/calls"; then fail "manual opening cancels a waiting automatic offer"; fi
unset TEST_FIRST_STEPS_MODE
pass "manual opening cancels a waiting automatic offer"

fresh_state installer
export TEST_FIRST_STEPS_REAL_SLEEP=1
touch "$test_tmp/block-done"
mkdir -p "$state_dir/installing"
printf '%s\n' seclists >"$state_dir/installing/tool"
monarch-setup-first-steps tools-state | jq -e '.active == "" and .lastResult.tool == "seclists" and .lastResult.code == 130' >/dev/null
[[ ! -e $state_dir/installing ]] || fail "interrupted installation state is recovered"
pass "stale installation state is recovered before displaying tool availability"

: >"$test_tmp/block-install"
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -e $test_tmp/installer-started ]] || break
  /usr/bin/sleep 0.02
done
[[ -f $test_tmp/installer-started ]] || fail "installation starts in the presentation terminal"
[[ $(head -n 1 "$test_tmp/calls") == 'msg plugin monarch/first-steps:panel all skip' ]] || fail "tool installation hides the guide before opening the terminal"
if monarch-setup-first-steps install-tool seclists >/dev/null 2>&1; then fail "duplicate installation is excluded"; fi
monarch-setup-first-steps tools-state | jq -e '.active == "seclists"' >/dev/null
rm "$test_tmp/block-install"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.installed.seclists and .active == "" and .lastResult.code == 0' >/dev/null
[[ $(<"$test_tmp/installer-args") == seclists ]] || fail "the existing wordlist installer receives its package"
pass "installation state is stored outside the runtime and excludes duplicate jobs"
if grep -q '^msg panel-open ' "$test_tmp/calls"; then fail "tool result stays visible until acknowledged"; fi
rm "$test_tmp/block-done"
for ((attempt = 0; attempt < 200; attempt++)); do
  grep -q '^panel-opened monarch/first-steps:panel$' "$test_tmp/calls" && break
  /usr/bin/sleep 0.02
done
grep -q '^panel-opened monarch/first-steps:panel$' "$test_tmp/calls" || fail "tool installation returns to the guide"
jq -e '.phase == "software"' "$test_tmp/context" >/dev/null
pass "tool installation hides the guide and resumes the software step only after acknowledgement"

rm "$test_tmp/installed" "$test_tmp/installer-started"
export TEST_FIRST_STEPS_EXIT=42
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.active == "" and .lastResult.code == 42' >/dev/null
if monarch-setup-first-steps install-tool unknown >/dev/null 2>&1; then fail "unknown tools cannot launch installers"; fi
pass "failed installations release their slot and unknown tools are rejected"

unset TEST_FIRST_STEPS_EXIT
fresh_state delayed-installer
rm -f "$test_tmp/installer-started"
export TEST_FIRST_STEPS_LAUNCH=delayed
: >"$test_tmp/block-install"
monarch-setup-first-steps install-tool seclists
monarch-setup-first-steps tools-state | jq -e '.active == "seclists"' >/dev/null
if monarch-setup-first-steps install-tool seclists >/dev/null 2>&1; then fail "a delayed terminal retains its installation slot"; fi
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -e $test_tmp/installer-started ]] || break
  /usr/bin/sleep 0.02
done
[[ -f $test_tmp/installer-started ]] || fail "the delayed terminal starts its installer"
monarch-setup-first-steps tools-state | jq -e '.active == "seclists"' >/dev/null
pass "a terminal launcher can exit before its installer starts without losing ownership"

runner_pid=$(<"$test_tmp/runner-pid")
installer_pid=$(<"$test_tmp/installer-pid")
kill -KILL "$runner_pid"
monarch-setup-first-steps tools-state | jq -e '.active == "seclists"' >/dev/null
if monarch-setup-first-steps install-tool seclists >/dev/null 2>&1; then fail "a surviving installer retains the lock after its wrapper dies"; fi
kill -KILL "$installer_pid"
for ((attempt = 0; attempt < 100; attempt++)); do
  state=$(monarch-setup-first-steps tools-state)
  if jq -e '.active == ""' >/dev/null <<<"$state"; then break; fi
  /usr/bin/sleep 0.02
done
jq -e '.active == "" and .lastResult.code == 130' >/dev/null <<<"$state"
[[ ! -e $state_dir/installing ]] || fail "a killed installation can be recovered"
pass "an abruptly killed wrapper preserves a live installer and recovers after all processes stop"

unset TEST_FIRST_STEPS_REAL_SLEEP
export TEST_FIRST_STEPS_LAUNCH=never
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.active == "" and .lastResult.code == 124' >/dev/null
expired_command=$(<"$test_tmp/terminal-command")
pass "an accepted terminal that never starts its installer releases its reservation"

export TEST_FIRST_STEPS_REAL_SLEEP=1 TEST_FIRST_STEPS_LAUNCH=delayed
rm -f "$test_tmp/installer-started"
monarch-setup-first-steps install-tool seclists
if bash -c "$expired_command" >/dev/null 2>&1; then fail "an expired terminal cannot take over a new installation"; fi
monarch-setup-first-steps tools-state | jq -e '.active == "seclists" and .lastResult == null' >/dev/null
rm "$test_tmp/block-install"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.installed.seclists and .active == "" and .lastResult.code == 0' >/dev/null
pass "a stale terminal is rejected and installation succeeds after crash recovery"

rm "$test_tmp/installed"
export TEST_FIRST_STEPS_LAUNCH=failure
mkdir "$state_dir/installing"
printf '%s\n' seclists >"$state_dir/installing/tool"
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.active == "" and .lastResult.code == 42' >/dev/null
for ((attempt = 0; attempt < 200; attempt++)); do
  grep -q '^panel-opened monarch/first-steps:panel$' "$test_tmp/calls" && break
  /usr/bin/sleep 0.02
done
grep -q '^panel-opened monarch/first-steps:panel$' "$test_tmp/calls" || fail "tool launch failure restores the guide"
jq -e '.phase == "software"' "$test_tmp/context" >/dev/null
pass "terminal launch failure releases the reservation and preserves its exit status"

fresh_state network
monarch-setup-first-steps record network
TEST_FIRST_STEPS_NETWORK=offline monarch-setup-first-steps tools-state | jq -e '.connected == false' >/dev/null
monarch-setup-first-steps tools-state | jq -e '.connected == true' >/dev/null
export TEST_FIRST_STEPS_MODE=network-visit
monarch-setup-first-steps visit network
jq -e '.phase == "network"' "$test_tmp/context" >/dev/null
[[ $(head -n 1 "$test_tmp/calls") == 'msg plugin monarch/first-steps:panel all skip' ]] || fail "network visit hides the persistent guide first"
grep -q '^msg panel-open monarch/network:panel$' "$test_tmp/calls"
[[ ! -f $test_tmp/network-open ]] || fail "network visit waits for the panel to close"
monarch-setup-first-steps record update
if TEST_FIRST_STEPS_NETWORK_LAUNCH=failure monarch-setup-first-steps visit network; then fail "network launch failure is reported"; fi
jq -e '.phase == "update"' "$test_tmp/context" >/dev/null
pass "network status covers offline and connected users and visits return to the saved phase"

monarch-setup-first-steps record network
for child in monarch/network:speedtest monarch/network:disk-speedtest monarch/wifi-qr:panel; do
  : > "$test_tmp/calls"
  TEST_FIRST_STEPS_CHILD="$child" monarch-setup-first-steps visit network
  grep -q '^msg panel-open monarch/first-steps:panel ' "$test_tmp/calls" || fail "closing $child does not return to the guide"
done
: > "$test_tmp/calls"
TEST_FIRST_STEPS_CHILD=monarch/menu:panel monarch-setup-first-steps visit network
if grep -q '^msg panel-open monarch/first-steps:panel ' "$test_tmp/calls"; then fail "network return steals focus from an unrelated panel"; fi
pass "network subpanels return to the guide while unrelated panels keep focus"

wait_for_update_result() {
  local attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    if monarch-setup-first-steps tools-state | jq -e --argjson code "$1" '.active == "" and .updateResult.code == $code' >/dev/null; then return 0; fi
    /usr/bin/sleep 0.02
  done
  fail "update result $1 was not recorded"
}

wait_for_update_return() {
  local attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    if grep -q '^panel-opened monarch/first-steps:panel$' "$test_tmp/calls"; then return 0; fi
    /usr/bin/sleep 0.02
  done
  fail "update did not return to the guide"
}

fresh_state update-offline
if TEST_FIRST_STEPS_NETWORK=offline monarch-setup-first-steps install-tool update >/dev/null 2>&1; then fail "an offline update is rejected"; fi
[[ ! -e $state_dir/installing && ! -s $test_tmp/calls ]] || fail "offline updates leave the guide open without reserving an installer"
pass "offline users can keep browsing without launching an update"

fresh_state update-success
export TEST_FIRST_STEPS_PANEL_DELAY=0.2
unset TEST_FIRST_STEPS_LAUNCH TEST_FIRST_STEPS_EXIT
touch "$test_tmp/block-update" "$test_tmp/block-done"
monarch-setup-first-steps install-tool update
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ ! -f $test_tmp/update-started ]] || break
  /usr/bin/sleep 0.02
done
[[ -f $test_tmp/update-started ]] || fail "update starts in a terminal"
[[ -z $(<"$test_tmp/update-args") ]] || fail "the updater owns its check and confirmation without forced unattended mode"
[[ $(head -n 1 "$test_tmp/calls") == 'msg plugin monarch/first-steps:panel all skip' ]] || fail "update hides the persistent guide first"
monarch-setup-first-steps tools-state | jq -e '.active == "update"' >/dev/null
if monarch-setup-first-steps install-tool seclists >/dev/null 2>&1; then fail "an update excludes tool installations"; fi
if monarch-setup-first-steps install-tool update >/dev/null 2>&1; then fail "duplicate updates are excluded"; fi
rm "$test_tmp/block-update"
wait_for_update_result 0
if grep -q '^msg panel-open ' "$test_tmp/calls"; then fail "the terminal result stays visible until acknowledged"; fi
rm "$test_tmp/block-done"
wait_for_update_return
jq -e '.phase == "update"' "$test_tmp/context" >/dev/null
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.updateResult.code == 0 and .lastResult.tool == "seclists"' >/dev/null
pass "updates share the installation lock, return after acknowledgement and retain their result across tool installs"
unset TEST_FIRST_STEPS_PANEL_DELAY

# A remembered success must not permanently prevent a newly available update.
rm "$test_tmp/update-started"
: > "$test_tmp/calls"
monarch-setup-first-steps install-tool update
wait_for_update_result 0
wait_for_update_return
[[ -f $test_tmp/update-started ]] || fail "a later update is not suppressed by a previous successful run"
pass "a successful first update does not prevent subsequent updates offered by a fresh check"

fresh_state update-cancel
rm "$test_tmp/update-started"
export TEST_FIRST_STEPS_CONFIRM=1
monarch-setup-first-steps install-tool update
wait_for_update_result 130
wait_for_update_return
[[ ! -f $test_tmp/update-started ]] || fail "declining confirmation never runs the updater"
unset TEST_FIRST_STEPS_CONFIRM
export TEST_FIRST_STEPS_EXIT=42
: >"$test_tmp/calls"
monarch-setup-first-steps install-tool update
wait_for_update_result 42
wait_for_update_return
unset TEST_FIRST_STEPS_EXIT
pass "cancelled updates are not marked successful and failed updates can be retried"

fresh_state update-launch-failure
export TEST_FIRST_STEPS_LAUNCH=failure
rm -f "$test_tmp/launcher-failed"
cat >"$runtime/bin/flock" <<'EOF'
#!/bin/bash
if [[ $* == 8 && -f $TEST_FIRST_STEPS/launcher-failed ]] &&
  [[ $(tr '\0' ' ' <"/proc/$PPID/cmdline") == *" install-tool update"* ]]; then
  touch "$TEST_FIRST_STEPS/finish-waiting"
  while [[ ! -f $TEST_FIRST_STEPS/finish-release ]]; do /usr/bin/sleep 0.02; done
fi
exec /usr/bin/flock "$@"
EOF
chmod +x "$runtime/bin/flock"
monarch-setup-first-steps install-tool update
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ -f $test_tmp/finish-waiting ]] && break
  /usr/bin/sleep 0.02
done
[[ -f $test_tmp/finish-waiting ]] || fail "launcher did not reach result publication"
state=$(monarch-setup-first-steps tools-state)
touch "$test_tmp/finish-release"
jq -e '.active == "update" and .updateResult == null' <<<"$state" >/dev/null ||
  fail "status polling recovered the launch before its failure result was recorded"
wait_for_update_result 42
wait_for_update_return
rm "$runtime/bin/flock"
pass "terminal launch failure restores the guide with a retryable update result"

fresh_state update-locked
unset TEST_FIRST_STEPS_LAUNCH
export TEST_FIRST_STEPS_MODE=locked
monarch-setup-first-steps install-tool update
wait_for_update_result 0
for ((attempt = 0; attempt < 200; attempt++)); do
  grep -q '^msg status$' "$test_tmp/calls" && break
  /usr/bin/sleep 0.02
done
grep -q '^msg status$' "$test_tmp/calls" || fail "update return checks desktop availability"
if grep -q '^msg panel-open ' "$test_tmp/calls"; then fail "update return cannot open over a locked desktop"; fi
pass "finishing an update respects a locked desktop"

fresh_state update-interrupted
mkdir -p "$state_dir/installing"
printf '%s\n' update >"$state_dir/installing/tool"
monarch-setup-first-steps tools-state | jq -e '.active == "" and .updateResult.code == 130' >/dev/null
pass "an interrupted update remains retryable after its processes disappear"

cat > "$runtime/bin/monarch-update-available" <<'EOF'
#!/bin/bash
[[ $* == '--all --json' ]] || exit 99
printf '%s\n' '{"status":"current","count":0}'
exit 1
EOF
chmod +x "$runtime/bin/monarch-update-available"
code=0
monarch-setup-first-steps check-updates > "$test_tmp/check-result" || code=$?
(( code == 1 )) || fail "the guide preserves the unified no-update exit status"
jq -e '.status == "current" and .count == 0' "$test_tmp/check-result" >/dev/null
pass "the guide queries all updates as JSON and preserves the no-update response"
