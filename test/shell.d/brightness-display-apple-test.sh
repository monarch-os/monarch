#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/dev/usb" "$test_root/runtime"
ln -s /dev/null "$test_root/dev/usb/hiddev0"

cat >"$test_root/bin/asdcontrol" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ASD_CALLS"
if [[ $1 == --detect ]]; then
  printf '%s: Apple Studio Display\n' "$TEST_DEVICE"
elif (($# == 1)); then
  printf '%s: BRIGHTNESS=30000\n' "$1"
elif [[ ${TEST_FAIL_SET_ONCE:-false} == true && ! -e $TEST_SET_FAILED ]]; then
  touch "$TEST_SET_FAILED"
  exit 1
fi
STUB
cat >"$test_root/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo must not be called" >&2
exit 99
STUB
chmod +x "$test_root/bin/"*

wrapper="$ROOT/bin/monarch-brightness-display-apple"
calls="$test_root/asdcontrol.calls"
device="$test_root/dev/usb/hiddev0"
cache="$test_root/runtime/monarch-brightness-display-apple.device"

run_wrapper() {
  TEST_ASD_CALLS="$calls" TEST_DEVICE="$device" TEST_SET_FAILED="$test_root/set-failed" \
    MONARCH_HIDDEV_ROOT="$test_root/dev" XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_root/bin:/usr/bin" bash "$wrapper" "$@"
}

: >"$calls"
run_wrapper +5000
grep -qxF -- "--detect $device" "$calls" || fail "Apple display was not detected"
grep -qxF -- "$device -- +5000" "$calls" || fail "raw relative brightness stopped working"
[[ $(<"$cache") == "$device" ]] || fail "detected device was not cached"
pass "unprivileged wrapper detects and writes an Apple display"

: >"$calls"
run_wrapper 5%-
[[ $(<"$calls") == "$device -- -5%" ]] || fail "cached percentage decrement was not normalized"
pass "private cache avoids repeat detection"

: >"$calls"
[[ $(run_wrapper) == 50 ]] || fail "brightness read did not return a percentage"
[[ $(<"$calls") == "$device" ]] || fail "brightness read used an unexpected command"
pass "wrapper reports current brightness"

printf '%s\n' /dev/null >"$cache"
: >"$calls"
run_wrapper 50%
grep -qxF -- "--detect $device" "$calls" || fail "poisoned cache was trusted"
pass "wrapper rejects a cached non-hiddev path"

rm -f "$cache" "$test_root/set-failed"
: >"$calls"
TEST_FAIL_SET_ONCE=true run_wrapper +5%
[[ $(grep -cxF -- "--detect $device" "$calls") == 2 ]] || fail "failed write did not redetect"
[[ $(grep -cxF -- "$device -- +5%" "$calls") == 2 ]] || fail "failed write was not retried once"
pass "wrapper recovers from a stale hotplug cache"

for invalid in --force 101% 65536 +999999; do
  : >"$calls"
  if run_wrapper "$invalid" >/dev/null 2>&1; then
    fail "invalid brightness was accepted: $invalid"
  fi
  [[ ! -s $calls ]] || fail "invalid brightness reached asdcontrol: $invalid"
done
if run_wrapper 5% extra >/dev/null 2>&1; then
  fail "extra arguments were accepted"
fi
pass "closed brightness grammar rejects options, overflow and extra arguments"

[[ ! -e $ROOT/etc/sudoers.d/monarch-asdcontrol ]] || fail "Monarch still ships an asdcontrol sudoers rule"
if rg -n '\bsudo\b' "$wrapper" >/dev/null; then
  fail "Apple display wrapper still enters a privileged path"
fi
pass "Apple display control has no Monarch sudo boundary"
