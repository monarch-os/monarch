#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

system_root="$test_tmp/system"
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$system_root/etc/mkinitcpio.conf.d" \
  "$system_root/etc/systemd/resolved.conf.d" "$stub_bin"

for command in bash cmp cut install rm sha256sum; do
  ln -s "$(command -v "$command")" "$stub_bin/$command"
done

cat >"$stub_bin/mkinitcpio" <<'EOF'
#!/bin/bash
printf 'mkinitcpio %s\n' "$*" >>"$TEST_CALLS"
[[ ${TEST_MKINITCPIO_FAIL:-false} != "true" ]]
EOF
cat >"$stub_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_CALLS"
EOF
chmod +x "$stub_bin/mkinitcpio" "$stub_bin/systemctl"

hooks="$system_root/etc/mkinitcpio.conf.d/monarch_hooks.conf"
resolved="$system_root/etc/systemd/resolved.conf.d/10-disable-multicast.conf"
printf '%s\n' \
  'HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)' \
  'FILES=(/etc/vconsole.conf)' >"$hooks"
printf '%s\n' 'new hooks' >"$hooks.pacnew"
printf '%s\n' '[Resolve]' 'MulticastDNS=no' >"$resolved"
printf '%s\n' '[Resolve]' 'LLMNR=no' 'MulticastDNS=no' >"$resolved.pacnew"

if MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  TEST_MKINITCPIO_FAIL=true PATH="$stub_bin" \
  bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null; then
  fail "a failed initramfs rebuild did not stop reconciliation"
fi
[[ $(<"$hooks") == "new hooks" && -f $hooks.pacnew ]] ||
  fail "a failed initramfs rebuild did not preserve retry state"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null

[[ $(<"$hooks") == "new hooks" && ! -e $hooks.pacnew ]] ||
  fail "the stock v4 initramfs configuration was not adopted"
[[ $(<"$resolved") == $'[Resolve]\nLLMNR=no\nMulticastDNS=no' && ! -e $resolved.pacnew ]] ||
  fail "the stock v4 resolver configuration was not adopted"
[[ $(<"$calls") == $'mkinitcpio -P\nmkinitcpio -P\nsystemctl try-restart systemd-resolved' ]] ||
  fail "adopted system settings were not applied"
pass "stock v4 system settings adopt and apply their packaged replacements"

printf '%s\n' customized >"$hooks"
printf '%s\n' 'future hooks' >"$hooks.pacnew"
printf '%s\n' customized >"$resolved"
printf '%s\n' 'future resolver' >"$resolved.pacnew"
: >"$calls"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null

[[ $(<"$hooks") == "customized" && $(<"$hooks.pacnew") == "future hooks" ]] ||
  fail "a customized initramfs configuration was overwritten"
[[ $(<"$resolved") == "customized" && $(<"$resolved.pacnew") == "future resolver" ]] ||
  fail "a customized resolver configuration was overwritten"
[[ ! -s $calls ]] || fail "unchanged system settings were applied"
pass "customized v4 system settings retain their pacnew for manual review"

cat >"$stub_bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
printf 'limine-mkinitcpio%s\n' "${*:+ $*}" >>"$TEST_CALLS"
exit "${TEST_LIMINE_STATUS:-0}"
EOF
chmod +x "$stub_bin/limine-mkinitcpio"
printf '%s\n' \
  'HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)' \
  'FILES=(/etc/vconsole.conf)' >"$hooks"
: >"$calls"

if MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  TEST_LIMINE_STATUS=42 PATH="$stub_bin" \
  bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null; then
  fail "a failed Limine rebuild did not stop reconciliation"
else
  [[ $? == 42 ]] || fail "the Limine rebuild exit status was lost"
fi
[[ $(<"$hooks") == "future hooks" && -f $hooks.pacnew ]] ||
  fail "a failed Limine rebuild did not preserve retry state"
[[ $(<"$calls") == "limine-mkinitcpio" ]] ||
  fail "a failed Limine rebuild fell back to classic mkinitcpio" "$(<"$calls")"
pass "Limine failure propagates and keeps the pacnew without a classic fallback"
: >"$calls"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null

[[ $(<"$calls") == "limine-mkinitcpio" ]] ||
  fail "Limine rebuilds directly without a preliminary classic initramfs" "$(<"$calls")"
[[ $(<"$hooks") == "future hooks" && ! -e $hooks.pacnew ]] ||
  fail "the successful Limine retry did not complete adoption"
pass "Limine retries directly with stdin closed and clears the pacnew after success"
: >"$calls"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null

[[ ! -s $calls ]] || fail "completed adoption rebuilt the boot image again"
pass "completed adoption does not rebuild again"

printf '%s\n' customized >"$hooks"
printf '%s\n' 'next hooks' >"$hooks.pacnew"
MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh" </dev/null

[[ $(<"$hooks") == "customized" && $(<"$hooks.pacnew") == "next hooks" && ! -s $calls ]] ||
  fail "Limine adoption did not preserve customized hooks for manual review"
pass "customized hooks do not trigger a Limine rebuild"
