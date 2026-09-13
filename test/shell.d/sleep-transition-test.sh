#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export SLEEP_TEST_DIR="$test_tmp"
export PATH="$test_tmp/bin:$PATH"

cat >"$test_tmp/bin/supergfxctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SLEEP_TEST_DIR/calls"
case $1 in
  -g)
    [[ ${HANG_QUERY:-0} == 0 ]] || exec /usr/bin/sleep 30
    count=$(<"$SLEEP_TEST_DIR/queries")
    echo "$((count + 1))" >"$SLEEP_TEST_DIR/queries"
    if [[ -f $SLEEP_TEST_DIR/requested ]] && ((count >= ${QUERY_DELAY:-0})); then
      cp "$SLEEP_TEST_DIR/requested" "$SLEEP_TEST_DIR/mode"
    fi
    cat "$SLEEP_TEST_DIR/mode"
    ;;
  -m)
    [[ ${HANG_REQUEST:-0} == 0 ]] || exec /usr/bin/sleep 30
    [[ ${FAIL_REQUEST:-} != "$2" ]] || exit 23
    echo 0 >"$SLEEP_TEST_DIR/queries"
    echo "$2" >"$SLEEP_TEST_DIR/requested"
    ;;
esac
STUB
cat >"$test_tmp/bin/sleep" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$test_tmp/bin/"*

sed \
  -e "s|/usr/bin/supergfxctl|$test_tmp/bin/supergfxctl|g" \
  -e "s|state_file=/run/monarch-force-igpu|state_file=$test_tmp/marker|" \
  -e "s|-o root -g root|-o $(id -u) -g $(id -g)|" \
  "$ROOT/default/systemd/system-sleep/force-igpu" >"$test_tmp/hook"

prepare() {
  rm -f "$test_tmp/marker" "$test_tmp/requested"
  echo Integrated >"$test_tmp/mode"
  echo 0 >"$test_tmp/queries"
  : >"$test_tmp/calls"
}

prepare
SYSTEMD_SLEEP_ACTION=hibernate QUERY_DELAY=2 bash "$test_tmp/hook" pre suspend-then-hibernate
grep -qx -- '-m Vfio' "$test_tmp/calls" || fail "the real hibernate phase is ignored"
[[ $(<"$test_tmp/mode") == Vfio ]] || fail "the hook does not wait for the requested mode"
[[ -f $test_tmp/marker && $(stat -c %a "$test_tmp/marker") == 600 ]] || fail "the restore marker is not private"
pass "composite hibernation waits for the GPU to reach Vfio"

SYSTEMD_SLEEP_ACTION=hibernate bash "$test_tmp/hook" pre suspend-then-hibernate
[[ -f $test_tmp/marker ]] || fail "a repeated pre-hook forgets the original Integrated mode"
QUERY_DELAY=2 bash "$test_tmp/hook" post suspend-then-hibernate
[[ $(<"$test_tmp/mode") == Integrated && ! -e $test_tmp/marker ]] || fail "resume does not restore and clear the marker"
pass "repeated pre-hooks preserve the original mode until confirmed restoration"

prepare
if FAIL_REQUEST=Vfio bash "$test_tmp/hook" pre hibernate 2>"$test_tmp/error"; then
  fail "a refused mode transition succeeds"
fi
[[ -f $test_tmp/marker ]] || fail "a failed transition loses the restoration intent"
if FAIL_REQUEST=Vfio bash "$test_tmp/hook" post hibernate 2>"$test_tmp/error"; then
  fail "a failed resume reports success"
fi
! grep -qx -- '-m Integrated' "$test_tmp/calls" || fail "Integrated is requested before Vfio succeeds"
[[ -f $test_tmp/marker ]] || fail "resume failure discards its retry marker"
bash "$test_tmp/hook" post hibernate
[[ ! -e $test_tmp/marker ]] || fail "a retry cannot complete restoration"
pass "failed transitions remain retryable and stop later mode changes"

prepare
if QUERY_DELAY=100 bash "$test_tmp/hook" pre hibernate 2>"$test_tmp/error"; then
  fail "an unconfirmed mode transition succeeds"
fi
grep -q 'confirm' "$test_tmp/error" || fail "a stalled mode is not explained"
(( $(<"$test_tmp/queries") == 10 )) || fail "mode polling is not bounded"
pass "mode confirmation gives up after a bounded number of polls"

for stalled in HANG_QUERY HANG_REQUEST; do
  prepare
  result=0
  env "$stalled=1" /usr/bin/timeout 8s bash "$test_tmp/hook" pre hibernate 2>"$test_tmp/error" || result=$?
  ((result == 1)) || fail "$stalled was not handled by the hook's own timeout (exit $result)"
done
pass "blocked daemon reads and requests terminate within the hook's own deadline"

prepare
echo Hybrid >"$test_tmp/mode"
bash "$test_tmp/hook" pre hibernate
[[ ! -e $test_tmp/marker ]] || fail "Hybrid mode is claimed for restoration"
! grep -q '^-m ' "$test_tmp/calls" || fail "Hybrid mode is changed"
touch "$test_tmp/external"
ln -s "$test_tmp/external" "$test_tmp/marker"
if bash "$test_tmp/hook" pre hibernate; then
  fail "a redirected restore marker is accepted"
fi
[[ -L $test_tmp/marker ]] || fail "a redirected marker was silently replaced"
pass "other modes and invalid marker paths are left untouched"

mkdir -p "$test_tmp/leds/platform::kbd_backlight"
cat >"$test_tmp/bin/brightnessctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SLEEP_TEST_DIR/brightness"
STUB
chmod +x "$test_tmp/bin/brightnessctl"
sed "s|/sys/class/leds/|$test_tmp/leds/|g" \
  "$ROOT/default/systemd/system-sleep/keyboard-backlight" >"$test_tmp/keyboard"
SYSTEMD_SLEEP_ACTION=suspend bash "$test_tmp/keyboard" pre suspend-then-hibernate
[[ ! -e $test_tmp/brightness ]] || fail "the keyboard is disabled for ordinary suspend"
SYSTEMD_SLEEP_ACTION=hibernate bash "$test_tmp/keyboard" pre suspend-then-hibernate
grep -qx -- '-d platform::kbd_backlight set 0' "$test_tmp/brightness" || fail "the keyboard workaround misses composite hibernate"
pass "keyboard backlight follows the actual sleep action"
