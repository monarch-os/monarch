#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mock_bin="$test_root/bin"
state_file="$test_root/state"
log="$test_root/actions.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$WPA_TEST_LOG"
case "$*" in
  "is-enabled wpa_supplicant.service")
    state=$(<"$WPA_TEST_STATE")
    [[ $state != "masked-both" ]] || state="masked"
    printf '%s\n' "$state"
    [[ $state == "enabled" ]]
    ;;
  "unmask wpa_supplicant.service")
    [[ $WPA_TEST_UNMASK_FAILS == false ]] || exit 1
    state=$(<"$WPA_TEST_STATE")
    if [[ $state == "masked-both" ]]; then
      printf '%s\n' masked-runtime >"$WPA_TEST_STATE"
    else
      printf '%s\n' disabled >"$WPA_TEST_STATE"
    fi
    ;;
  "unmask --runtime wpa_supplicant.service")
    [[ $WPA_TEST_RUNTIME_UNMASK_FAILS == false ]] || exit 1
    printf '%s\n' disabled >"$WPA_TEST_STATE"
    ;;
  "is-active --quiet NetworkManager.service") [[ $WPA_TEST_NM_ACTIVE == true ]] ;;
  "restart NetworkManager.service") [[ $WPA_TEST_RESTART_FAILS == false ]] ;;
  *) exit 2 ;;
esac
EOF

cat >"$mock_bin/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli\t%s\n' "$*" >>"$WPA_TEST_LOG"
[[ $WPA_TEST_NMCLI_FAILS == false ]] || exit 1
printf '%s\n' "$WPA_TEST_DEVICES"
EOF
chmod +x "$mock_bin"/*

reconciler="$ROOT/install/reconcile/wpa-supplicant.sh"

reset_case() {
  printf '%s\n' "${1:-disabled}" >"$state_file"
  : >"$log"
  nm_active=true
  devices="wifi:unavailable"
  unmask_fails=false
  runtime_unmask_fails=false
  restart_fails=false
  nmcli_fails=false
}

run_reconciler() {
  WPA_TEST_LOG="$log" \
    WPA_TEST_STATE="$state_file" \
    WPA_TEST_NM_ACTIVE="$nm_active" \
    WPA_TEST_DEVICES="$devices" \
    WPA_TEST_UNMASK_FAILS="$unmask_fails" \
    WPA_TEST_RUNTIME_UNMASK_FAILS="$runtime_unmask_fails" \
    WPA_TEST_RESTART_FAILS="$restart_fails" \
    WPA_TEST_NMCLI_FAILS="$nmcli_fails" \
    PATH="$mock_bin:/usr/bin" \
    bash "$reconciler"
}

reset_case disabled
run_reconciler
[[ $(wc -l <"$log") == 1 ]] || fail "an unmasked service triggered recovery work"
grep -qxF $'systemctl\tis-enabled wpa_supplicant.service' "$log" ||
  fail "healthy state was not queried"
pass "healthy installations are left unchanged"

reset_case masked
run_reconciler
[[ $(<"$state_file") == "disabled" ]] || fail "the persistent mask survived"
grep -qxF $'systemctl\tunmask wpa_supplicant.service' "$log" ||
  fail "the persistent mask was not removed"
grep -qxF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "NetworkManager was not restarted for an unavailable radio"
pass "persistent masks are removed and unavailable Wi-Fi recovers"

: >"$log"
run_reconciler
[[ $(wc -l <"$log") == 1 ]] || fail "a completed repair was not idempotent"
pass "a completed repair is idempotent"

reset_case masked-runtime
run_reconciler
[[ $(<"$state_file") == "disabled" ]] || fail "the runtime mask survived"
grep -qxF $'systemctl\tunmask --runtime wpa_supplicant.service' "$log" ||
  fail "the runtime mask was not removed explicitly"
! grep -qxF $'systemctl\tunmask wpa_supplicant.service' "$log" ||
  fail "runtime-only state touched the persistent layer"
pass "runtime-only masks are removed from the right layer"

reset_case masked-both
run_reconciler
grep -qxF $'systemctl\tunmask wpa_supplicant.service' "$log" ||
  fail "the persistent half of a combined mask survived"
grep -qxF $'systemctl\tunmask --runtime wpa_supplicant.service' "$log" ||
  fail "the runtime half of a combined mask survived"
[[ $(<"$state_file") == "disabled" ]] || fail "the combined mask survived"
pass "persistent and runtime masks are both removed"

reset_case masked
nm_active=false
run_reconciler
! grep -qF $'nmcli\t' "$log" || fail "inactive NetworkManager triggered a device query"
! grep -qF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "inactive NetworkManager was started"
pass "inactive NetworkManager is not disturbed"

reset_case masked
devices=$'ethernet:connected\nwifi:disconnected'
run_reconciler
grep -qxF $'nmcli\t-t -f TYPE,STATE device' "$log" || fail "Wi-Fi state was not queried"
! grep -qF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "a usable Wi-Fi device triggered a restart"
pass "NetworkManager restarts only for unavailable Wi-Fi"

reset_case masked
nmcli_fails=true
run_reconciler
! grep -qF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "an unreadable device state triggered a restart"
pass "an unreadable device state does not trigger a blind restart"

reset_case masked
unmask_fails=true
if run_reconciler >/dev/null 2>&1; then
  fail "a failed persistent unmask was ignored"
fi
! grep -qF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "recovery continued after a failed unmask"
pass "persistent unmask failures remain retryable"

reset_case masked-runtime
runtime_unmask_fails=true
if run_reconciler >/dev/null 2>&1; then
  fail "a failed runtime unmask was ignored"
fi
! grep -qF $'systemctl\trestart NetworkManager.service' "$log" ||
  fail "recovery continued after a failed runtime unmask"
pass "runtime unmask failures remain retryable"

reset_case masked
restart_fails=true
run_reconciler
[[ $(<"$state_file") == "disabled" ]] || fail "a restart failure restored the mask"
pass "a NetworkManager restart failure does not undo the repair"

grep -qF 'reconcile/wpa-supplicant.sh' "$ROOT/install/reconcile/system.sh" ||
  fail "the system reconciler does not run the repair"
pass "the repair runs during system reconciliation"
