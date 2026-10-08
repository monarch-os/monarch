#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
system_root="$test_tmp/root"
mkdir -p "$system_root/etc/pam.d" "$test_tmp/bin"
export CALL_LOG="$test_tmp/calls" SENSOR_ROOT="$test_tmp/sensor"
printf '%s\n' 'auth sufficient pam_fprintd.so' \
  'auth [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed' \
  'auth include system-auth' >"$system_root/etc/pam.d/sudo"
cp "$system_root/etc/pam.d/sudo" "$test_tmp/original-pam"
mkdir -p "$system_root/var/lib/fprint/alice" "$system_root/var/lib/fprint/bob" "$test_tmp/alice"
touch "$system_root/var/lib/fprint/"{alice,bob}/print
mkdir -p "$SENSOR_ROOT/"{alice,bob}
touch "$SENSOR_ROOT/"{alice,bob}/print
cat >"$test_tmp/bin/fprintd-delete" <<'STUB'
#!/bin/bash
printf '%s\n' "device-delete $*" >>"$CALL_LOG"
[[ ${DEVICE_DELETE_STATUS:-0} == 0 ]] || exit "$DEVICE_DELETE_STATUS"
rm -f -- "$SENSOR_ROOT/$1/print"
STUB
cat >"$test_tmp/bin/id" <<'STUB'
#!/bin/bash
[[ $* == '-nu +1001' || $* == '-un' ]] || exit 1
printf '%s\n' "${FIXTURE_USER:-alice}"
STUB
cat >"$test_tmp/bin/getent" <<STUB
#!/bin/bash
printf '%s\n' 'alice:x:1001:1001::${test_tmp}/alice:/bin/bash'
STUB
cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
case $1 in
  fprintd-delete) exec "$@" ;;
  rm) [[ ${FAIL_DELETE:-0} != 1 || $2 != -rf ]] || exit 1; exec "$@" ;;
  sed) exec "$@" ;;
  *) exit 99 ;;
esac
STUB
for command in noctalia monarch-pkg-drop; do
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >>"$CALL_LOG"\n' "$command" >"$test_tmp/bin/$command"
done
chmod +x "$test_tmp/bin/"*
python3 - "$ROOT/bin/monarch-remove-security-fingerprint" "$test_tmp/remove" "$test_tmp" "$system_root" <<'PY'
from pathlib import Path
import sys
source, target, temp, system = sys.argv[1:]
s = Path(source).read_text().replace('EUID', 'FIXTURE_EUID')
s = s.replace('/usr/bin/fprintd-delete', 'fprintd-delete')
s = s.replace('/usr/bin/id', temp + '/bin/id').replace('/usr/bin/getent', temp + '/bin/getent')
for path in ('/etc/pam.d/', '/usr/local/bin/', '/var/lib/fprint/'):
  s = s.replace(path, system + path)
Path(target).write_text(s)
PY
export PATH="$test_tmp/bin:/usr/bin" FIXTURE_EUID=0 SUDO_UID=1001 HOME="$test_tmp/root-home" USER=bob
: >"$CALL_LOG"
if SUDO_UID=bad bash "$test_tmp/remove" >/dev/null 2>&1; then fail "invalid invoking UID is accepted"; fi
if FIXTURE_USER=../bob bash "$test_tmp/remove" >/dev/null 2>&1; then fail "unsafe account name is accepted"; fi
[[ ! -s $CALL_LOG ]] || fail "invalid identity changes authentication"
if DEVICE_DELETE_STATUS=1 bash "$test_tmp/remove" >/dev/null 2>&1; then fail "failed device deletion reports success"; fi
[[ -f $SENSOR_ROOT/alice/print && -f $system_root/var/lib/fprint/alice/print ]] ||
  fail "failed device deletion removes sensor or local retry data"
cmp "$test_tmp/original-pam" "$system_root/etc/pam.d/sudo" || fail "failed device deletion changes PAM"
! grep -Eq '^(rm |sed |monarch-pkg-drop )' "$CALL_LOG" ||
  fail "failed device deletion starts local or authentication teardown"
: >"$CALL_LOG"
if FAIL_DELETE=1 bash "$test_tmp/remove" >/dev/null 2>&1; then fail "failed print deletion reports success"; fi
[[ -f $system_root/var/lib/fprint/alice/print ]] || fail "failed teardown loses retry data"
cmp "$test_tmp/original-pam" "$system_root/etc/pam.d/sudo" || fail "failed deletion changes PAM"
! grep -Eq '^(monarch-pkg-drop |sed )' "$CALL_LOG" ||
  fail "failed print deletion changes authentication or packages"
: >"$CALL_LOG"
bash "$test_tmp/remove" >/dev/null
[[ ! -e $system_root/var/lib/fprint/alice && ! -e $SENSOR_ROOT/alice/print &&
  -f $system_root/var/lib/fprint/bob/print && -f $SENSOR_ROOT/bob/print ]] ||
  fail "fingerprint removal uses USER or deletes another account's prints"
[[ $(cat "$system_root/etc/pam.d/sudo") == 'auth include system-auth' ]] ||
  fail "successful teardown does not retain the password fallback"
device_line=$(grep -n '^device-delete alice$' "$CALL_LOG" | head -1 | cut -d: -f1)
rm_line=$(grep -n "^rm -rf -- $system_root/var/lib/fprint/alice$" "$CALL_LOG" | cut -d: -f1)
pkg_line=$(grep -n '^monarch-pkg-drop ' "$CALL_LOG" | cut -d: -f1)
(( device_line < rm_line && rm_line < pkg_line )) || fail "fingerprint packages are removed before saved prints"
pass "sudo teardown identifies the invoking account and preserves other accounts' saved prints"

mkdir -p "$system_root/var/lib/fprint/alice" "$test_tmp/alice/.config/noctalia" \
  "$test_tmp/alice/.local/state/monarch"
touch "$SENSOR_ROOT/alice/print" "$system_root/var/lib/fprint/alice/print" "$test_tmp/alice/.config/noctalia/monarch-fingerprint.toml" \
  "$test_tmp/alice/.local/state/monarch/fingerprint-enabled"
FIXTURE_EUID=1000 bash "$test_tmp/remove" >/dev/null
[[ ! -e $system_root/var/lib/fprint/alice && ! -e $test_tmp/alice/.config/noctalia/monarch-fingerprint.toml && \
  ! -e $test_tmp/alice/.local/state/monarch/fingerprint-enabled && -f $system_root/var/lib/fprint/bob/print ]] ||
  fail "ordinary teardown does not clean the caller's home and saved prints"
pass "ordinary teardown uses the account's home despite misleading HOME, USER and SUDO_UID"
