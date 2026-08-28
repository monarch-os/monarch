#!/bin/bash

source "${BASH_SOURCE[0]%/*}/base-test.sh"

apply_system="$ROOT/bin/monarch-apply-system"
apply_hardware="$ROOT/bin/monarch-apply-hardware"
user_stage="$ROOT/install/user/all.sh"
root_stage="$ROOT/install/config/all.sh"

for stage in config login post-install; do
  grep -qF "source \"\$MONARCH_INSTALL/$stage/all.sh\"" "$apply_system" ||
    fail "apply-system does not own the $stage root stage"
done
grep -qF 'monarch-apply-hardware --install-user "$install_user"' "$apply_system" ||
  fail "apply-system does not invoke root hardware setup"
pass "apply-system owns every root setup stage"

if grep -qF 'login/limine-snapper.sh' "$ROOT/install/login/all.sh"; then
  fail "login setup still invokes the legacy Limine/Snapper finalizer"
fi
grep -qE '^HOOKS=.*\bencrypt\b' "$ROOT/etc/mkinitcpio.conf.d/monarch_hooks.conf" ||
  fail "the packaged initramfs configuration has no encrypt hook"
pass "the package owns encrypted initramfs hooks without a login finalizer"

if grep -qF 'helpers/chroot.sh' "$apply_hardware"; then
  fail "hardware apply still depends on the legacy chroot helper"
fi
pass "hardware setup uses direct service activation"

if grep -qE 'input-group|docker|wireshark|kernel-modules|sudoers' "$user_stage"; then
  fail "user setup still contains a root-owned script"
fi
pass "user setup excludes root-owned scripts"

grep -qF 'hardware/input-group.sh' "$ROOT/install/hardware/all.sh" ||
  fail "input group is absent from root hardware setup"
input_group_owners=$(grep -l 'input-group.sh' "$root_stage" "$ROOT/install/hardware/all.sh" "$user_stage" | wc -l)
(( input_group_owners == 1 )) ||
  fail "input group has more than one phase owner"
pass "input group has one root owner"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
printf 'false\n' >"$test_tmp/fail.sh"
: >"$test_tmp/install.log"
if MONARCH_INSTALL_LOG_FILE="$test_tmp/install.log" bash -c \
  'set -e; source "$1"; run_logged "$2"' bash \
  "$ROOT/install/helpers/logging.sh" "$test_tmp/fail.sh"; then
  fail "logging swallowed a failed setup script"
fi
grep -qF 'Failed:' "$test_tmp/install.log" ||
  fail "logging lost the failed setup-script record"
pass "logging records failures under errexit"
