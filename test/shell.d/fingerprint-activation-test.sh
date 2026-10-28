#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" PATH="$test_tmp/bin:/usr/bin" MONARCH_PATH="$ROOT"
export CALL_LOG="$test_tmp/calls"
mkdir -p "$HOME" "$test_tmp/bin" "$test_tmp/etc/pam.d"
python3 - "$ROOT/bin/monarch-setup-security-fingerprint" "$test_tmp/setup" "$test_tmp" <<'PY'
from pathlib import Path
import sys
source, destination, root = sys.argv[1:]
text = Path(source).read_text()
for old, new in (('/etc/pam.d/', root + '/etc/pam.d/'),
    ('/usr/bin/monarch-hw-laptop-closed', root + '/packaged-gate'),
    ('sudo /usr/bin/bash /usr/share/monarch/install/reconcile/fingerprint-gate.sh', ': # migration tested separately')):
  assert old in text, f'fixture target changed: {old!r}'
  text = text.replace(old, new)
Path(destination).write_text(text)
PY
cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
case $1 in
  fprintd-enroll|install|sed|tee) exec "$@" ;;
  *) exit 99 ;;
esac
STUB
cat >"$test_tmp/bin/fprintd-list" <<'STUB'
#!/bin/bash
echo sensor
STUB
cat >"$test_tmp/bin/fprintd-enroll" <<'STUB'
#!/bin/bash
printf '%s\n' enroll >>"$CALL_LOG"
exit "${ENROLL_STATUS:-0}"
STUB
cat >"$test_tmp/bin/fprintd-verify" <<'STUB'
#!/bin/bash
printf '%s\n' verify >>"$CALL_LOG"
exit "${VERIFY_STATUS:-0}"
STUB
for command in monarch-pkg-add noctalia; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/$command"
done
chmod +x "$test_tmp/bin/"*
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/packaged-gate"
chmod +x "$test_tmp/packaged-gate"
printf '%s\n' 'auth include system-auth' >"$test_tmp/etc/pam.d/sudo"
cp "$test_tmp/etc/pam.d/sudo" "$test_tmp/original"

for stage in enroll verify; do
  : >"$CALL_LOG"
  if ENROLL_STATUS=$([[ $stage == enroll ]] && echo 1 || echo 0) \
    VERIFY_STATUS=$([[ $stage == verify ]] && echo 1 || echo 0) \
    bash "$test_tmp/setup" >/dev/null; then
    fail "failed fingerprint $stage reports successful setup"
  fi
  cmp "$test_tmp/original" "$test_tmp/etc/pam.d/sudo" || fail "failed fingerprint setup modifies PAM"
  [[ ! -e $test_tmp/etc/pam.d/polkit-1 && ! -e $test_tmp/gate && \
    ! -e $HOME/.config/noctalia/monarch-fingerprint.toml && \
    ! -e $HOME/.local/state/monarch/fingerprint-enabled ]] ||
    fail "failed fingerprint setup enables authentication"
done
pass "failed fingerprint enrollment or verification leaves authentication unchanged"

mv "$test_tmp/packaged-gate" "$test_tmp/saved-gate"
if bash "$test_tmp/setup" >/dev/null; then
  fail "missing packaged gate enabled fingerprint authentication"
fi
cmp "$test_tmp/original" "$test_tmp/etc/pam.d/sudo" || fail "missing packaged gate changed PAM"
[[ ! -e $HOME/.config/noctalia/monarch-fingerprint.toml ]] || fail "missing packaged gate enabled lock fingerprint"
mv "$test_tmp/saved-gate" "$test_tmp/packaged-gate"
pass "missing packaged gate leaves authentication unchanged"

: >"$CALL_LOG"
bash "$test_tmp/setup" >/dev/null
grep -Fq 'fingerprint = true' "$HOME/.config/noctalia/monarch-fingerprint.toml" || fail "verified fingerprint is not enabled in Noctalia"
[[ -f $HOME/.local/state/monarch/fingerprint-enabled ]] || fail "verified fingerprint has no marker"
[[ $(sed -n '1p' "$test_tmp/etc/pam.d/sudo") == *'pam_exec.so quiet'* && \
  $(sed -n '2p' "$test_tmp/etc/pam.d/sudo") == *'pam_fprintd.so'* ]] || fail "the lid gate no longer skips just fingerprint"
grep -qF "pam_exec.so quiet $test_tmp/packaged-gate" "$test_tmp/etc/pam.d/sudo" ||
  fail "PAM does not reference the packaged gate"
[[ $(grep -c 'include system-auth' "$test_tmp/etc/pam.d/polkit-1") == 4 ]] || fail "fingerprint loses password policy fallback"
! grep -q '^install ' "$CALL_LOG" || fail "setup copied a session helper into root runtime"
verify_line=$(grep -n '^verify$' "$CALL_LOG" | cut -d: -f1)
pam_line=$(grep -n '^sed ' "$CALL_LOG" | head -1 | cut -d: -f1)
(( verify_line < pam_line )) || fail "PAM is enabled before verification"
pass "verified fingerprints activate PAM, the lid gate and Noctalia in that order"
