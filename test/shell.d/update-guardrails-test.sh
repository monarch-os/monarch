#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
mkdir -p "$stub_bin" "$test_home" "$runtime_dir"
export MONARCH_PATH="$test_tmp/packaged-runtime"
mkdir -p "$MONARCH_PATH"

write_stub() {
  local name="$1"
  local body="$2"

  printf '#!/bin/bash\n%s\n' "$body" >"$stub_bin/$name"
  chmod +x "$stub_bin/$name"
}

run_update() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  MONARCH_UPDATE_LOGGED=1 \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  STEP_LOG="$test_tmp/steps" \
    "$ROOT/bin/monarch-update" "$@"
}

steps=(
  monarch-update-requires-free-space
  monarch-update-pkg-prune
  monarch-snapshot
  monarch-update-switch-branch
  monarch-update-stay-awake
  monarch-update-git
  monarch-update-keyring
  monarch-update-system-pkgs
  monarch-reconcile
  monarch-update-aur-pkgs
  monarch-update-orphan-pkgs
  monarch-hook
  monarch-update-analyze-logs
  monarch-update-restart
)

for step in "${steps[@]}"; do
  write_stub "$step" 'printf "%s unattended=%s args=%s\n" "${0##*/}" "${MONARCH_UPDATE_UNATTENDED:-}" "$*" >>"$STEP_LOG"'
done

write_stub monarch-update-available '
[[ $* == "--all --json" ]] || exit 99
[[ -z ${CHECK_LOG:-} ]] || printf "check\n" >>"$CHECK_LOG"
if [[ -n ${KEYRING_TRACE:-} ]]; then
  printf "check\n" >>"$KEYRING_TRACE"
  if [[ ! -e $KEYRING_MARKER || ${RETRY_CHECK_FAILURE:-0} == 1 ]]; then
    echo '\''{"status":"error","count":null,"reason":"repositories-unavailable"}'\''
    exit 2
  fi
fi
if [[ ${BAD_CHECK_JSON:-0} == 1 ]]; then echo invalid; exit 0; fi
if [[ ${PARTIAL_AUR_CHECK:-0} == 1 ]]; then
  echo '\''{"status":"available","count":2,"repositories":2,"aur":null,"complete":false,"warnings":[{"source":"aur","reason":"aur-unavailable"}]}'\''
  exit 0
fi
case ${CHECK_STATUS:-0} in
  0) echo '\''{"status":"available","count":3}'\'' ;;
  1) echo '\''{"status":"current","count":0}'\'' ;;
  *) echo '\''{"status":"error","count":null}'\'' ;;
esac
exit "${CHECK_STATUS:-0}"'
write_stub monarch-update-confirm 'printf "confirmation\n" >>"$STEP_LOG"; exit "${CONFIRM_STATUS:-0}"'

: >"$test_tmp/steps"
run_update -y >/dev/null
cut -d' ' -f1 "$test_tmp/steps" >"$test_tmp/names"
cat >"$test_tmp/expected" <<'EOF'
monarch-update-requires-free-space
monarch-update-pkg-prune
monarch-snapshot
monarch-update-stay-awake
monarch-update-git
monarch-update-keyring
monarch-update-system-pkgs
monarch-reconcile
monarch-update-aur-pkgs
monarch-update-orphan-pkgs
monarch-hook
monarch-update-analyze-logs
monarch-update-stay-awake
monarch-update-restart
EOF
diff -u "$test_tmp/expected" "$test_tmp/names" || fail "update guardrail ordering"
grep -q '^monarch-update-system-pkgs unattended=1' "$test_tmp/steps" ||
  fail "unattended update state reaches package updates"
pass "update orders preflight, pruning, snapshot, reconciliation and hooks"
grep -q '^monarch-hook .*args=--strict post-update$' "$test_tmp/steps" || fail "updates must propagate post-update hook failures"

cp "$stub_bin/monarch-update-keyring" "$test_tmp/keyring-step"
write_stub monarch-update-keyring '
printf "%s\n" "${0##*/}" >>"$STEP_LOG"
printf "keyring\n" >>"$KEYRING_TRACE"
[[ ${KEYRING_REPAIR_FAIL:-0} == 0 ]] || exit 42
touch "$KEYRING_MARKER"'
write_stub gum '
[[ $1 == confirm ]] || exit 99
printf "repair-confirmation\n" >>"$KEYRING_TRACE"
exit "${REPAIR_CONFIRM_STATUS:-0}"'
export KEYRING_TRACE="$test_tmp/keyring-trace" KEYRING_MARKER="$test_tmp/keyring-refreshed"
for mode in interactive unattended; do
  args=()
  [[ $mode != "unattended" ]] || args=(-y)
  for after_repair in 0 1; do
    rm -f "$KEYRING_MARKER"
    : >"$KEYRING_TRACE"
    : >"$test_tmp/steps"
    CHECK_STATUS="$after_repair" run_update "${args[@]}" >/dev/null
    [[ $(grep -E '^(check|keyring)$' "$KEYRING_TRACE") == $'check\nkeyring\ncheck' ]] || fail "keyring repair must precede exactly one retry"
    [[ $(grep -c '^monarch-update-keyring' "$test_tmp/steps") == 1 ]] || fail "keyrings refreshed more than once"
    [[ $(grep -c '^monarch-update-stay-awake .*args=start' "$test_tmp/steps") == 1 ]] || fail "repair does not retain one inhibitor through the update"
    grep -q '^monarch-reconcile ' "$test_tmp/steps" || fail "repaired check cannot reach finalization"
    if [[ $mode == "interactive" ]]; then
      grep -q '^repair-confirmation$' "$KEYRING_TRACE" || fail "interactive keyring repair is not offered"
    elif grep -q confirmation "$KEYRING_TRACE"; then
      fail "unattended repair prompts"
    fi
  done
done
for failure in repair retry cancel-repair cancel-update; do
  rm -f "$KEYRING_MARKER"
  : >"$KEYRING_TRACE"
  : >"$test_tmp/steps"
  result=0
  case "$failure" in
    repair) KEYRING_REPAIR_FAIL=1 run_update -y >/dev/null 2>&1 || result=$?; expected=42 ;;
    retry) RETRY_CHECK_FAILURE=1 run_update -y >/dev/null 2>&1 || result=$?; expected=2 ;;
    cancel-repair) REPAIR_CONFIRM_STATUS=1 run_update >/dev/null 2>&1 || result=$?; expected=130 ;;
    cancel-update) CONFIRM_STATUS=1 run_update >/dev/null 2>&1 || result=$?; expected=130 ;;
  esac
  (( result == expected )) || fail "$failure returned $result instead of $expected"
  if grep -Eq '^monarch-(snapshot|reconcile|update-(pkg-prune|system-pkgs))' "$test_tmp/steps"; then
    fail "$failure continued the update transaction"
  fi
  if [[ $failure == "cancel-repair" ]]; then
    [[ ! -s $test_tmp/steps ]] || fail "declining repair changes system state"
  else
    grep -q '^monarch-update-stay-awake .*args=stop' "$test_tmp/steps" || fail "$failure leaks the repair inhibitor"
  fi
  (( $(grep -c '^keyring$' "$KEYRING_TRACE" || true) <= 1 )) || fail "$failure repeats keyring repair"
done
unset KEYRING_TRACE KEYRING_MARKER
cp "$test_tmp/keyring-step" "$stub_bin/monarch-update-keyring"
pass "repository checks can recover through one keyring refresh, with cancellation and failure cleanup"

for mode in interactive unattended; do
  args=()
  [[ $mode != "unattended" ]] || args=(-y)
  : >"$test_tmp/steps"
  CHECK_STATUS=1 run_update "${args[@]}" >/dev/null
  if grep -Eq '^(confirmation|monarch-update-(requires-free-space|pkg-prune|git|keyring|system-pkgs|aur-pkgs)|monarch-snapshot)' "$test_tmp/steps"; then
    fail "$mode current system asks for a package update or reruns package preparation"
  fi
  for stage in monarch-reconcile monarch-update-orphan-pkgs monarch-hook monarch-update-analyze-logs monarch-update-restart; do
    grep -q "^$stage " "$test_tmp/steps" || fail "$mode current system skips $stage"
  done
  for check_status in 2 124; do
    : >"$test_tmp/steps"
    result=0
    CHECK_STATUS="$check_status" run_update "${args[@]}" >/dev/null 2>&1 || result=$?
    (( result == 2 )) || fail "$mode check failure is not reported"
    [[ ! -s $test_tmp/steps ]] || fail "$mode failed check performs maintenance"
  done
done
pass "current packages skip package work but finish configuration; unverifiable checks stop before maintenance"

# A prior updater may have installed every upgrade before a later stage failed.
# Retry without transaction markers: current packages must not hide that failure.
for failed_stage in monarch-reconcile monarch-hook; do
  cp "$stub_bin/$failed_stage" "$test_tmp/recovery-stage"
  write_stub "$failed_stage" 'printf "%s\n" "${0##*/}" >>"$STEP_LOG"; exit 42'
  : >"$test_tmp/steps"
  result=0
  run_update -y >/dev/null 2>&1 || result=$?
  (( result == 42 )) || fail "$failed_stage failure is not propagated"
  grep -q '^monarch-update-system-pkgs ' "$test_tmp/steps" || fail "the failure did not follow package installation"
  : >"$test_tmp/steps"
  result=0
  CHECK_STATUS=1 run_update -y >/dev/null 2>&1 || result=$?
  (( result == 42 )) || fail "a current-package retry silently ignores $failed_stage failure"
  grep -qx "$failed_stage" "$test_tmp/steps" || fail "retry did not attempt $failed_stage"
  cp "$test_tmp/recovery-stage" "$stub_bin/$failed_stage"
  : >"$test_tmp/steps"
  CHECK_STATUS=1 run_update -y >/dev/null
  if grep -q '^monarch-update-system-pkgs ' "$test_tmp/steps"; then fail "recovery unnecessarily reinstalls packages"; fi
  grep -q "^$failed_stage " "$test_tmp/steps" || fail "recovery skipped $failed_stage"
  grep -q '^monarch-update-restart ' "$test_tmp/steps" || fail "recovery did not finish the post-update stages"
done
pass "post-package failures remain visible and recover on a current-package retry without pending markers"

for mode in interactive unattended; do
  args=()
  [[ $mode != "unattended" ]] || args=(-y)
  : >"$test_tmp/steps"
  PARTIAL_AUR_CHECK=1 run_update "${args[@]}" >"$test_tmp/partial-output"
  grep -q '^monarch-update-keyring ' "$test_tmp/steps" || fail "$mode AUR outage blocks keyring updates"
  grep -q '^monarch-update-system-pkgs ' "$test_tmp/steps" || fail "$mode AUR outage blocks repository updates"
  grep -q '^monarch-reconcile ' "$test_tmp/steps" || fail "$mode partial update skips reconciliation"
  if grep -q '^monarch-update-aur-pkgs ' "$test_tmp/steps"; then fail "$mode partial update retries the unavailable AUR"; fi
  grep -q AUR "$test_tmp/partial-output" || fail "$mode partial update hides its AUR warning"
done
pass "AUR outages warn and skip AUR while allowing repository and security updates"

: >"$test_tmp/steps"
result=0
BAD_CHECK_JSON=1 run_update -y >/dev/null 2>&1 || result=$?
(( result == 2 )) || fail "malformed availability data is accepted"
[[ ! -s $test_tmp/steps ]] || fail "malformed availability data starts maintenance"
CHECK_LOG="$test_tmp/checks" run_update >/dev/null
[[ $(head -n 1 "$test_tmp/steps") == confirmation ]] || fail "confirmation must precede maintenance"
[[ $(<"$test_tmp/checks") == check ]] || fail "the updater verifies availability before confirmation"
: >"$test_tmp/steps"
result=0
CONFIRM_STATUS=1 run_update >/dev/null 2>&1 || result=$?
(( result == 130 )) || fail "cancellation is not distinguishable from success"
[[ $(<"$test_tmp/steps") == confirmation ]] || fail "cancelled update performs maintenance"
: >"$test_tmp/checks"
CHECK_LOG="$test_tmp/checks" CHECK_STATUS=2 run_update -y --branch dev >/dev/null
[[ ! -s $test_tmp/checks ]] || fail "an explicit branch change depends on current-branch availability"
pass "confirmed updates run normally, cancellation is distinct, and explicit branch changes bypass the availability gate"

git init -q "$test_tmp/git-runtime"
for check_status in 1 2; do
  : >"$test_tmp/steps"
  : >"$test_tmp/checks"
  MONARCH_PATH="$test_tmp/git-runtime" CHECK_LOG="$test_tmp/checks" CHECK_STATUS="$check_status" run_update -y >/dev/null
  [[ ! -s $test_tmp/checks ]] || fail "a package-only check gates a Git runtime update"
  grep -q '^monarch-update-git ' "$test_tmp/steps" || fail "Git runtime never reaches its source update"
  grep -q '^monarch-update-system-pkgs ' "$test_tmp/steps" || fail "Git runtime skips the normal transaction"
done
pass "Git runtimes still pull source with plain -y when package availability cannot require an update"

write_stub monarch-update-system-pkgs 'exit 1'
: >"$test_tmp/steps"
if run_update -y >/dev/null 2>&1; then
  fail "failed package update stops the transaction"
fi
grep -q '^monarch-update-stay-awake .*args=stop' "$test_tmp/steps" ||
  fail "failed update releases its inhibitor"
if grep -Eq '^monarch-(reconcile|hook|update-restart) ' "$test_tmp/steps"; then
  fail "failed package update reaches later transaction steps"
fi
pass "update failure releases temporary state and stops later steps"

cp "$stub_bin/monarch-update-system-pkgs" "$test_tmp/failing-system-step"
write_stub monarch-update-system-pkgs 'exit 0'
cp "$stub_bin/monarch-update-aur-pkgs" "$test_tmp/aur-step"
write_stub monarch-update-aur-pkgs 'exit 42'
: >"$test_tmp/steps"
result=0
run_update -y >/dev/null 2>&1 || result=$?
(( result == 42 )) || fail "failed AUR update is not propagated"
if grep -Eq '^monarch-(hook|update-(orphan-pkgs|restart))' "$test_tmp/steps"; then fail "failed AUR update reaches later steps"; fi
grep -q '^monarch-update-stay-awake .*args=stop' "$test_tmp/steps" || fail "failed AUR update leaks its inhibitor"
cp "$test_tmp/aur-step" "$stub_bin/monarch-update-aur-pkgs"
cp "$test_tmp/failing-system-step" "$stub_bin/monarch-update-system-pkgs"
pass "the updater reports AUR failures and stops finalization"

write_stub monarch-update-system-pkgs 'printf "%s\n" "${0##*/}" >>"$STEP_LOG"'
write_stub monarch-snapshot 'touch "$SNAPSHOT_MARKER"'
write_stub monarch-update-pkg-prune 'sleep 2'
snapshot_marker="$test_tmp/snapshot"
SNAPSHOT_MARKER="$snapshot_marker" run_update -y >/dev/null 2>&1 &
first_update_pid=$!
sleep 0.2
set +e
second_output=$(SNAPSHOT_MARKER="$snapshot_marker" run_update -y 2>&1)
second_status=$?
set -e
wait "$first_update_pid"
(( second_status != 0 )) || fail "concurrent update is rejected"
[[ $second_output == *"already running"* ]] || fail "concurrent refusal is actionable"
pass "update lock rejects overlapping transactions"

write_stub systemd-inhibit 'printf "%s\n" "$$" >"$INHIBIT_PID_FILE"; exec sleep 30'
write_stub pkexec 'exec "$@"'
write_stub noctalia 'exit 0'
caffeine_state="$runtime_dir/monarch/caffeine"
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-toggle-idle" claim update-owner
[[ $(<"$caffeine_state") == "update-owner" ]] || fail "Caffeine claim records its owner"
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-toggle-idle" stay-awake
[[ $(<"$caffeine_state") == "user" ]] || fail "explicit Caffeine choice replaces update ownership"
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-toggle-idle" release update-owner
[[ -f $caffeine_state ]] || fail "stale Caffeine owner released a user choice"
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-toggle-idle" allow-idle
pass "Caffeine ownership preserves a newer explicit user choice"

write_stub monarch-toggle-idle '
state_file="$XDG_RUNTIME_DIR/monarch/caffeine"
case "$1" in
  stay-awake | claim)
    mkdir -p "$(dirname "$state_file")"
    printf "%s\n" "${2:-user}" >"$state_file"
    ;;
  allow-idle | release)
    if [[ $1 != "release" || $(<"$state_file") == "${2:-}" ]]; then
      rm -f "$state_file"
    fi
    ;;
esac'
lock_target="$runtime_dir/monarch-update.lock"
INHIBIT_PID_FILE="$test_tmp/inhibitor" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-stay-awake" start
for _ in {1..50}; do
  [[ -s $test_tmp/inhibitor ]] && break
  sleep 0.02
done
inhibitor_pid=$(<"$test_tmp/inhibitor")
for fd in /proc/"$inhibitor_pid"/fd/*; do
  [[ -e $fd ]] || continue
  [[ $(readlink -f "$fd" 2>/dev/null) != "$(readlink -f "$lock_target")" ]] ||
    fail "sleep inhibitor inherited the update lock"
done
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-stay-awake" stop
kill -0 "$inhibitor_pid" 2>/dev/null && fail "sleep inhibitor survived stop"
pass "sleep inhibitor cannot retain the update lock and is stopped reliably"

linger="$test_tmp/linger"
daemon_pid_file="$test_tmp/daemon.pid"
printf '#!/bin/bash\nprintf "%%s\\n" "$$" >"$1"\nexec sleep 30\n' >"$linger"
chmod +x "$linger"

HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-lock" run bash -c 'setsid -f "$1" "$2"' bash "$linger" "$daemon_pid_file"
for _ in {1..50}; do
  [[ -s $daemon_pid_file ]] && break
  sleep 0.02
done
daemon_pid=$(<"$daemon_pid_file")
kill -0 "$daemon_pid" 2>/dev/null || fail "daemonized child did not survive the lock wrapper"
for fd in /proc/"$daemon_pid"/fd/*; do
  [[ -e $fd ]] || continue
  [[ $(readlink -f "$fd" 2>/dev/null) != "$(readlink -f "$lock_target")" ]] ||
    fail "daemonized child inherited the update lock"
done
HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-lock" run true
kill "$daemon_pid"
pass "daemonized update children cannot retain the transaction lock"

mkdir -p "$runtime_dir/monarch-update-stay-awake" "$runtime_dir/monarch"
printf '%s\n' old-update >"$runtime_dir/monarch-update-stay-awake/idle-owner"
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" monarch-toggle-idle stay-awake
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-stay-awake" stop
[[ -f $runtime_dir/monarch/caffeine ]] || fail "stale cleanup removed a newer user choice"
pass "inhibitor cleanup preserves pre-existing and newer Caffeine state"

write_stub df 'printf "Avail\n%s\n" "$TEST_AVAILABLE_BYTES"'
set +e
disk_output=$(TEST_AVAILABLE_BYTES=$((9 * 1024 * 1024 * 1024)) PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-requires-free-space" 2>&1)
disk_status=$?
set -e
(( disk_status == 1 )) || fail "low disk space blocks the update"
[[ $disk_output == *"10 GiB"* ]] || fail "low disk space explains the requirement"
MONARCH_UPDATE_FORCE=1 TEST_AVAILABLE_BYTES=0 PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-requires-free-space"
pass "disk preflight blocks unsafe updates and supports the explicit override"

write_stub df 'printf "Avail\nunknown\n"'
set +e
disk_output=$(PATH="$stub_bin:$ROOT/bin:$PATH" "$ROOT/bin/monarch-update-requires-free-space" 2>&1)
disk_status=$?
set -e
(( disk_status == 1 )) || fail "invalid disk-space measurement fails closed"
[[ $disk_output == *"MONARCH_UPDATE_FORCE=1"* ]] || fail "disk measurement failure explains its override"
pass "disk preflight fails closed when free space cannot be measured"

write_stub df 'printf "Avail\n%s\n" "$TEST_AVAILABLE_BYTES"'
write_stub monarch-update-pkg-prune 'printf "%s unattended=%s args=%s\n" "${0##*/}" "${MONARCH_UPDATE_UNATTENDED:-}" "$*" >>"$STEP_LOG"'
write_stub monarch-snapshot 'printf "%s unattended=%s args=%s\n" "${0##*/}" "${MONARCH_UPDATE_UNATTENDED:-}" "$*" >>"$STEP_LOG"'
: >"$test_tmp/steps"
TEST_AVAILABLE_BYTES=$((12 * 1024 * 1024 * 1024)) run_update -y --branch dev >/dev/null
preflight_line=$(grep -n '^monarch-update-requires-free-space ' "$test_tmp/steps" | cut -d: -f1)
switch_line=$(grep -n '^monarch-update-switch-branch ' "$test_tmp/steps" | cut -d: -f1)
snapshot_line=$(grep -n '^monarch-snapshot ' "$test_tmp/steps" | cut -d: -f1)
(( preflight_line < snapshot_line && snapshot_line < switch_line )) ||
  fail "branch update mutates before preflight and snapshot"
grep -q '^monarch-update-switch-branch .*args=dev$' "$test_tmp/steps" ||
  fail "branch update does not forward its selected branch"
pass "branch updates enter the common transaction before mutating Git state"

write_stub paccache 'exit 0'
write_stub sudo 'printf "%s\n" "$*" >"$PACCACHE_LOG"'
PACCACHE_LOG="$test_tmp/paccache" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-pkg-prune" >/dev/null
grep -Eq '^paccache -rk2$' "$test_tmp/paccache" || fail "package prune retains two cache versions"
pass "package cache pruning preserves two rollback versions"

prune_output=$(MONARCH_PACCACHE_BIN="$test_tmp/missing-paccache" \
  PATH="$stub_bin:/usr/bin" "$ROOT/bin/monarch-update-pkg-prune" 2>&1)
[[ $prune_output != *"command not found"* ]] || fail "missing paccache produces a shell error"
[[ $prune_output == *"Skipping package cache pruning"* ]] || fail "missing paccache is not explained"
pass "package cache pruning is skipped cleanly when pacman-contrib is absent"

stay_awake_stub="$stub_bin/monarch-update-stay-awake"
mv "$stay_awake_stub" "$stay_awake_stub.disabled"
rm -f "$runtime_dir/monarch/caffeine"
write_stub monarch-update-keyring 'touch "$INTERRUPT_MARKER"; sleep 30'
write_stub monarch-update-pkg-prune 'exit 0'
write_stub monarch-snapshot 'exit 0'
write_stub systemd-inhibit 'exec sleep 30'
interrupt_marker="$test_tmp/interrupt-started"
TEST_AVAILABLE_BYTES=$((12 * 1024 * 1024 * 1024)) \
  INTERRUPT_MARKER="$interrupt_marker" \
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  MONARCH_UPDATE_LOGGED=1 \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  STEP_LOG="$test_tmp/steps" \
  setsid "$ROOT/bin/monarch-update" -y >/dev/null 2>&1 &
interrupt_pid=$!
for _ in {1..100}; do
  [[ -f $interrupt_marker && -s $runtime_dir/monarch-update-stay-awake/inhibit-pid ]] && break
  sleep 0.02
done
[[ -f $interrupt_marker ]] || fail "interrupt test did not enter the guarded transaction"
kill -TERM -- "-$interrupt_pid"
wait "$interrupt_pid" 2>/dev/null || true
mv "$stay_awake_stub.disabled" "$stay_awake_stub"
for _ in {1..100}; do
  [[ ! -e $runtime_dir/monarch-update-stay-awake ]] && break
  sleep 0.02
done
if [[ -e $runtime_dir/monarch-update-stay-awake ]]; then
  find "$runtime_dir/monarch-update-stay-awake" -maxdepth 1 -printf '%f\n' >&2
  fail "interrupted update left inhibitor state"
fi
[[ ! -e $runtime_dir/monarch/caffeine ]] || fail "interrupted update left Caffeine enabled"
HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-lock" run true
pass "SIGTERM releases inhibitor state and the update lock"

# Exercise the real helpers as well as the orchestration stubs: their exit
# status is the outcome recorded by the first-steps guide.
write_stub pacman '[[ $* == -Qm ]] || exit 99; echo "dependency-only-aur 1"'
write_stub monarch-pkg-aur-accessible 'exit "${AUR_ACCESS_STATUS:-0}"'
write_stub yay 'touch "$AUR_CALLED"; exit "${AUR_EXIT_STATUS:-0}"'
export AUR_CALLED="$test_tmp/aur-called"
result=0
AUR_EXIT_STATUS=42 PATH="$stub_bin:$ROOT/bin:$PATH" "$ROOT/bin/monarch-update-aur-pkgs" >/dev/null 2>&1 || result=$?
(( result == 42 )) || fail "the real AUR helper hides yay failure"
[[ -f $AUR_CALLED ]] || fail "AUR packages installed as dependencies are skipped"
rm "$AUR_CALLED"
AUR_ACCESS_STATUS=1 PATH="$stub_bin:$ROOT/bin:$PATH" "$ROOT/bin/monarch-update-aur-pkgs" >/dev/null
[[ ! -e $AUR_CALLED ]] || fail "an unreachable AUR still invokes yay"
pass "the real AUR helper updates foreign dependencies and propagates yay errors"

mkdir -p "$test_home/.config/monarch/hooks/post-update.d"
printf '#!/bin/bash\nexit 42\n' > "$test_home/.config/monarch/hooks/post-update"
printf '#!/bin/bash\ntouch "$HOME/later-hook"\n' > "$test_home/.config/monarch/hooks/post-update.d/20-later"
HOME="$test_home" "$ROOT/bin/monarch-hook" post-update >/dev/null
[[ -e $test_home/later-hook ]] || fail "ordinary hooks no longer tolerate failures"
rm "$test_home/later-hook"
result=0
HOME="$test_home" "$ROOT/bin/monarch-hook" --strict post-update >/dev/null 2>&1 || result=$?
(( result == 42 )) || fail "strict hooks hide failure"
[[ ! -e $test_home/later-hook ]] || fail "strict hooks continue after failure"
printf '#!/bin/bash\nexit 0\n' > "$test_home/.config/monarch/hooks/post-update"
HOME="$test_home" "$ROOT/bin/monarch-hook" --strict post-update >/dev/null
[[ -e $test_home/later-hook ]] || fail "strict hook retry does not converge"
pass "real post-update hooks can fail strictly while default hooks stay tolerant"
