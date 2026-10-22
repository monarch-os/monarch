#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
(( EUID != 0 )) || { echo "Run this fixture test unprivileged" >&2; exit 1; }
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export MONARCH_ROOT_FILE_TEST_ROOT="$test_tmp"
export MONARCH_ROOT_FILE_TEST_RUNTIME="$test_tmp/usr/share/monarch"
export MONARCH_PATH="$test_tmp/hostile"
mkdir -p "$MONARCH_ROOT_FILE_TEST_RUNTIME" "$test_tmp/"{usr/bin,usr/local/bin,etc/pam.d}
mkdir -p "$MONARCH_PATH/bin"
printf '#!/bin/bash\ntouch "%s"\n' "$test_tmp/hostile-executed" >"$MONARCH_PATH/bin/monarch-hw-laptop-closed"
chmod +x "$MONARCH_PATH/bin/monarch-hw-laptop-closed"
chmod 700 "$test_tmp"
gate='auth      [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed'
printf '%s\nauth    sufficient pam_fprintd.so\nauth include admin-policy\n' "$gate" >"$test_tmp/etc/pam.d/sudo"
printf '# administrator comment\n%s\nauth sufficient pam_fprintd.so\nauth include system-auth\n' "$gate" >"$test_tmp/etc/pam.d/polkit-1"
chmod 640 "$test_tmp/etc/pam.d/polkit-1"
printf '%s\n' "$gate custom-argument" >"$test_tmp/etc/pam.d/custom"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/usr/local/bin/monarch-hw-laptop-closed"
cp "$test_tmp/etc/pam.d/sudo" "$test_tmp/original"
if bash "$ROOT/install/reconcile/fingerprint-gate.sh"; then
  fail "missing replacement was accepted"
fi
cmp "$test_tmp/original" "$test_tmp/etc/pam.d/sudo" || fail "missing replacement changed PAM"
[[ -f $test_tmp/usr/local/bin/monarch-hw-laptop-closed ]] || fail "premature helper cleanup"
cp "$test_tmp/usr/local/bin/monarch-hw-laptop-closed" "$test_tmp/usr/bin/monarch-hw-laptop-closed"
chmod 755 "$test_tmp/usr/bin/monarch-hw-laptop-closed"
chmod 777 "$test_tmp/usr/bin/monarch-hw-laptop-closed"
if bash "$ROOT/install/reconcile/fingerprint-gate.sh"; then
  fail "writable packaged replacement was accepted"
fi
cmp "$test_tmp/original" "$test_tmp/etc/pam.d/sudo" || fail "unsafe replacement changed PAM"
chmod 755 "$test_tmp/usr/bin/monarch-hw-laptop-closed"
bash "$ROOT/install/reconcile/fingerprint-gate.sh"
grep -qxF "${gate/\/usr\/local\/bin/\/usr\/bin}" "$test_tmp/etc/pam.d/sudo" || fail "legacy gate not migrated"
grep -qxF 'auth include admin-policy' "$test_tmp/etc/pam.d/sudo" || fail "admin policy changed"
grep -qxF "${gate/\/usr\/local\/bin/\/usr\/bin}" "$test_tmp/etc/pam.d/polkit-1" || fail "polkit legacy gate not migrated"
grep -qxF '# administrator comment' "$test_tmp/etc/pam.d/polkit-1" || fail "PAM comments changed"
[[ $(stat -c %a "$test_tmp/etc/pam.d/polkit-1") == 640 ]] || fail "PAM mode changed"
grep -qxF "$gate custom-argument" "$test_tmp/etc/pam.d/custom" || fail "custom gate changed"
[[ -f $test_tmp/usr/local/bin/monarch-hw-laptop-closed ]] || fail "referenced custom helper removed"
rm "$test_tmp/etc/pam.d/custom"
bash "$ROOT/install/reconcile/fingerprint-gate.sh"
[[ ! -e $test_tmp/usr/local/bin/monarch-hw-laptop-closed ]] || fail "unreferenced identical legacy helper retained"
cp "$test_tmp/etc/pam.d/sudo" "$test_tmp/once"
bash "$ROOT/install/reconcile/fingerprint-gate.sh"
cmp "$test_tmp/once" "$test_tmp/etc/pam.d/sudo" || fail "migration not idempotent"
[[ ! -e $test_tmp/hostile-executed ]] || fail "session helper was executed"
pass "packaged fingerprint gate fails closed, preserves admin PAM, cleans safely and is idempotent"

grep -vF '/usr/bin/monarch-hw-laptop-closed' "$test_tmp/etc/pam.d/sudo" >"$test_tmp/ungated"
mv "$test_tmp/ungated" "$test_tmp/etc/pam.d/sudo"
bash "$ROOT/install/reconcile/fingerprint-gate.sh"
grep -qxF "${gate/\/usr\/local\/bin/\/usr\/bin}" "$test_tmp/etc/pam.d/sudo" ||
  fail "reconciliation no longer repairs a missing gate for the stock fingerprint module"
pass "stock fingerprint authentication acquires a missing packaged lid gate"
