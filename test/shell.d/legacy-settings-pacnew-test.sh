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

cat >"$stub_bin/mkinitcpio" <<'EOF'
#!/bin/bash
printf 'mkinitcpio %s\n' "$*" >>"$TEST_CALLS"
EOF
cat >"$stub_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_CALLS"
EOF
chmod +x "$stub_bin/"*

hooks="$system_root/etc/mkinitcpio.conf.d/monarch_hooks.conf"
resolved="$system_root/etc/systemd/resolved.conf.d/10-disable-multicast.conf"
printf '%s\n' \
  'HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)' \
  'FILES=(/etc/vconsole.conf)' >"$hooks"
printf '%s\n' 'new hooks' >"$hooks.pacnew"
printf '%s\n' '[Resolve]' 'MulticastDNS=no' >"$resolved"
printf '%s\n' '[Resolve]' 'LLMNR=no' 'MulticastDNS=no' >"$resolved.pacnew"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin:/usr/bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh"

[[ $(<"$hooks") == "new hooks" && ! -e $hooks.pacnew ]] ||
  fail "the stock v4 initramfs configuration was not adopted"
[[ $(<"$resolved") == $'[Resolve]\nLLMNR=no\nMulticastDNS=no' && ! -e $resolved.pacnew ]] ||
  fail "the stock v4 resolver configuration was not adopted"
[[ $(<"$calls") == $'mkinitcpio -P\nsystemctl try-restart systemd-resolved' ]] ||
  fail "adopted system settings were not applied"
pass "stock v4 system settings adopt and apply their packaged replacements"

printf '%s\n' customized >"$hooks"
printf '%s\n' 'future hooks' >"$hooks.pacnew"
printf '%s\n' customized >"$resolved"
printf '%s\n' 'future resolver' >"$resolved.pacnew"
: >"$calls"

MONARCH_RECONCILE_SYSTEM_ROOT="$system_root" TEST_CALLS="$calls" \
  PATH="$stub_bin:/usr/bin" bash "$ROOT/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh"

[[ $(<"$hooks") == customized && $(<"$hooks.pacnew") == "future hooks" ]] ||
  fail "a customized initramfs configuration was overwritten"
[[ $(<"$resolved") == customized && $(<"$resolved.pacnew") == "future resolver" ]] ||
  fail "a customized resolver configuration was overwritten"
[[ ! -s $calls ]] || fail "unchanged system settings were applied"
pass "customized v4 system settings retain their pacnew for manual review"
