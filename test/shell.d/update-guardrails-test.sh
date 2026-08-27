#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
mkdir -p "$stub_bin" "$test_home" "$runtime_dir"

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
  monarch-migrate
  monarch-update-aur-pkgs
  monarch-update-orphan-pkgs
  monarch-hook
  monarch-update-analyze-logs
  monarch-update-restart
)

for step in "${steps[@]}"; do
  write_stub "$step" 'printf "%s unattended=%s args=%s\n" "${0##*/}" "${MONARCH_UPDATE_UNATTENDED:-}" "$*" >>"$STEP_LOG"'
done

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
monarch-migrate
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
pass "update orders preflight, pruning, snapshot, packages, migrations and hooks"

write_stub monarch-update-system-pkgs 'exit 1'
: >"$test_tmp/steps"
if run_update -y >/dev/null 2>&1; then
  fail "failed package update stops the transaction"
fi
grep -q '^monarch-update-stay-awake .*args=stop' "$test_tmp/steps" ||
  fail "failed update releases its inhibitor"
if grep -Eq '^monarch-(migrate|hook|update-restart) ' "$test_tmp/steps"; then
  fail "failed package update reaches later transaction steps"
fi
pass "update failure releases temporary state and stops later steps"

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

write_stub sudo 'printf "%s\n" "$*" >"$PACCACHE_LOG"'
PACCACHE_LOG="$test_tmp/paccache" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-pkg-prune" >/dev/null
grep -Eq '^paccache -rk2$' "$test_tmp/paccache" || fail "package prune retains two cache versions"
pass "package cache pruning preserves two rollback versions"

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
