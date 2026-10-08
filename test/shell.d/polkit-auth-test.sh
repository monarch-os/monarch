#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
system_root="$test_tmp/root"
runtime="$system_root/usr/share/monarch"
pam="$system_root/etc/pam.d/polkit-1"
mkdir -p "$runtime" "${pam%/*}"
export MONARCH_ROOT_FILE_TEST_ROOT="$system_root" MONARCH_ROOT_FILE_TEST_RUNTIME="$runtime"
reconcile="$ROOT/install/reconcile/polkit-auth.sh"
fprint='auth sufficient pam_fprintd.so'
fido='auth sufficient pam_u2f.so cue authfile=/etc/fido2/fido2'
gate='auth [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed'

for prefix in '' "$fprint" "$fido" "$gate"$'\n'"$fprint" \
  "$fido"$'\n'"$gate"$'\n'"$fprint" "$gate"$'\n'"$fprint"$'\n'"$fido"; do
  {
    printf '#%%PAM-1.0\n%s\n\n' "$prefix"
    printf '%s\n' 'auth required pam_unix.so' 'account required pam_unix.so' \
      'password required pam_unix.so' 'session required pam_unix.so'
  } >"$pam"
  chmod 640 "$pam"
  bash "$reconcile" >/dev/null
  [[ $(grep -c 'include system-auth' "$pam") == 4 && $(stat -c '%a' "$pam") == 640 ]] ||
    fail "recognized polkit stacks do not inherit system authentication policy"
  [[ -z $prefix ]] || grep -Fq "$prefix" "$pam" || fail "polkit repair drops enrolled authentication methods"
  inode=$(stat -c '%i' "$pam")
  bash "$reconcile"
  [[ $(stat -c '%i' "$pam") == "$inode" ]] || fail "polkit repair is not idempotent"
done
pass "legacy polkit stacks retain fingerprint and FIDO2 with system-auth fallback"

for extra in 'auth required pam_deny.so' 'auth sufficient pam_fprintd.so timeout=30' \
  'auth [success=2 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed'; do
  printf '%s\n' "$extra" 'auth required pam_unix.so' 'account required pam_unix.so' \
    'password required pam_unix.so' 'session required pam_unix.so' >"$pam"
  before=$(sha256sum "$pam")
  bash "$reconcile"
  [[ $(sha256sum "$pam") == "$before" ]] || fail "polkit repair overwrites administrator configuration"
done
cp "$pam" "$test_tmp/external"
rm "$pam"
ln -s "$test_tmp/external" "$pam"
if bash "$reconcile" >/dev/null 2>&1; then
  fail "polkit repair accepts a symlink"
fi
[[ $(sha256sum "$test_tmp/external" | cut -d' ' -f1) == "${before%% *}" ]] ||
  fail "polkit repair changes a symlink target"
pass "polkit repair preserves custom policy and rejects unsafe publication paths"

for setup in fingerprint fido2; do
  grep -Fq 'account   include system-auth' "$ROOT/bin/monarch-setup-security-$setup" ||
    fail "new $setup polkit setup bypasses system-auth"
done
grep -Fq 'sudo bash /usr/share/monarch/install/reconcile/polkit-auth.sh' "$ROOT/install/reconcile/system.sh" ||
  fail "the privileged polkit reconciler is not pinned to the packaged runtime"
