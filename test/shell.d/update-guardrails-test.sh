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
write_stub monarch-toggle-idle '
state_file="$XDG_RUNTIME_DIR/monarch/caffeine"
case "$1" in
  stay-awake)
    mkdir -p "$(dirname "$state_file")"
    touch "$state_file"
    ;;
  allow-idle)
    rm -f "$state_file"
    ;;
esac'
lock_target="$runtime_dir/monarch-update.lock"
exec 9>"$lock_target"
INHIBIT_PID_FILE="$test_tmp/inhibitor" \
  MONARCH_UPDATE_LOCK_FD=9 \
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

mkdir -p "$runtime_dir/monarch-update-stay-awake" "$runtime_dir/monarch"
printf '%s\n' old-update >"$runtime_dir/monarch-update-stay-awake/idle-owner"
printf '%s\n' newer-user-choice >"$runtime_dir/monarch/caffeine"
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

write_stub sudo 'printf "%s\n" "$*" >"$PACCACHE_LOG"'
PACCACHE_LOG="$test_tmp/paccache" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/monarch-update-pkg-prune" >/dev/null
grep -Eq '^paccache -rk2$' "$test_tmp/paccache" || fail "package prune retains two cache versions"
pass "package cache pruning preserves two rollback versions"
