#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

old_id=11111111111111111111111111111111
foreign_id=22222222222222222222222222222222
fixture="$test_tmp/root"
preserved="$test_tmp/preserved.conf"

mkdir -p "$fixture/boot/$old_id" "$fixture/boot/$foreign_id" \
  "$fixture/usr/share/monarch/install/assets/limine"
touch "$fixture/boot/$old_id/local" "$fixture/boot/$foreign_id/foreign"
printf 'interface_branding: Monarch\n' >"$fixture/usr/share/monarch/install/assets/limine/limine.conf"
cat >"$fixture/boot/limine.conf" <<EOF
interface_branding: Monarch
/+Monarch
comment: machine-id=$old_id
path: boot():/EFI/Linux/monarch_linux-cachyos.efi#aaaa

/Windows
protocol: efi
path: boot():/EFI/Microsoft/Boot/bootmgfw.efi

/+Foreign Linux
comment: machine-id=$foreign_id
path: boot():/EFI/Linux/foreign_linux-cachyos.efi#bbbb

/EFI fallback
comment: Default EFI loader
path: boot():/EFI/BOOT/BOOTX64.EFI
EOF

MONARCH_FACTORY_RESET_LIB_ONLY=true source "$ROOT/bin/monarch-system-factory-reset"
LOG_FILE="$test_tmp/factory-reset.log"
reset_limine_config "$fixture" /boot "$old_id" "$preserved"

grep -q '^/Windows' "$preserved"
grep -q "machine-id=$foreign_id" "$preserved"
! grep -q "machine-id=$old_id" "$preserved"
! grep -q '^/EFI fallback' "$preserved"
[[ -f $fixture/boot/$foreign_id/foreign ]]
[[ ! -e $fixture/boot/$old_id ]]
grep -q '^interface_branding: Monarch$' "$fixture/boot/limine.conf"

security_fixture="$test_tmp/security-root"
mkdir -p "$security_fixture/etc/sudoers.d" \
  "$security_fixture/var/lib/monarch/provisioning"
printf '%s\n' 'ALL ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol' \
  >"$security_fixture/etc/sudoers.d/asdcontrol"
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol' \
  >"$security_fixture/etc/sudoers.d/monarch-asdcontrol"
printf '%s\n' audio input video \
  >"$security_fixture/var/lib/monarch/provisioning/groups"
printf '%s\n' keep >"$security_fixture/etc/sudoers.d/local-admin"

retire_factory_privilege_grants "$security_fixture"

[[ ! -e $security_fixture/etc/sudoers.d/asdcontrol ]]
[[ ! -e $security_fixture/etc/sudoers.d/monarch-asdcontrol ]]
[[ $(<"$security_fixture/etc/sudoers.d/local-admin") == keep ]]
[[ $(<"$security_fixture/var/lib/monarch/provisioning/groups") == $'audio\nvideo' ]]

external_groups="$test_tmp/external-groups"
printf '%s\n' input >"$external_groups"
ln -sf "$external_groups" "$security_fixture/var/lib/monarch/provisioning/groups"
retire_factory_privilege_grants "$security_fixture"
[[ ! -e $security_fixture/var/lib/monarch/provisioning/groups ]]
[[ $(<"$external_groups") == input ]]

mkdir -p "$security_fixture/usr/share/monarch/bin" \
  "$security_fixture/var/lib/pacman/local/asdcontrol-0.6.0-1"
printf '%s\n' old >"$security_fixture/usr/share/monarch/bin/monarch-brightness-display-apple"
printf '%s\n' old >"$security_fixture/var/lib/pacman/local/asdcontrol-0.6.0-1/install"
wrapper_source="$test_tmp/monarch-brightness-display-apple"
rule_source="$test_tmp/70-asdcontrol.rules"
lifecycle_source="$test_tmp/asdcontrol.install"
printf '%s\n' '#!/bin/bash' current >"$wrapper_source"
chmod 0755 "$wrapper_source"
for id in 1114 1116 1118 9243; do
  printf 'SUBSYSTEM=="usbmisc", KERNEL=="hiddev*", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="%s", TAG+="uaccess"\n' "$id"
done >"$rule_source"
cat >"$lifecycle_source" <<'EOF'
ASDCONTROL_FACTORY_RULE=/etc/udev/rules.d/70-monarch-asdcontrol.rules
remove_factory_fallback() { :; }
supported_hiddev_nodes() { :; }
post_remove() { remove_factory_fallback; supported_hiddev_nodes; }
EOF

stage_current_apple_display_access \
  "$security_fixture" "$wrapper_source" "$rule_source" "$lifecycle_source"

cmp -s "$wrapper_source" \
  "$security_fixture/usr/share/monarch/bin/monarch-brightness-display-apple"
cmp -s "$rule_source" \
  "$security_fixture/etc/udev/rules.d/70-monarch-asdcontrol.rules"
cmp -s "$lifecycle_source" \
  "$security_fixture/var/lib/pacman/local/asdcontrol-0.6.0-1/install"

printer_fixture="$test_tmp/printer-root"
printer_log="$test_tmp/printer-pacman.log"
mkdir -p "$printer_fixture/etc/systemd/system/multi-user.target.wants"
ln -s /usr/lib/systemd/system/cups-browsed.service \
  "$printer_fixture/etc/systemd/system/multi-user.target.wants/cups-browsed.service"
cat >"$test_tmp/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_PACMAN_LOG"
if [[ $* == *' -Qq '* ]]; then
  echo cups-browsed
fi
EOF
chmod +x "$test_tmp/pacman"

export TEST_PACMAN_LOG="$printer_log"
retire_factory_printer_discovery "$printer_fixture" "$test_tmp/pacman"

[[ ! -e $printer_fixture/etc/systemd/system/multi-user.target.wants/cups-browsed.service ]]
[[ -f $printer_fixture/var/lib/monarch/reconcile/cups-browsed-removed ]]
grep -qxF -- "--root $printer_fixture -R --print cups-browsed" "$printer_log"
grep -qxF -- "--root $printer_fixture -R --noconfirm cups-browsed" "$printer_log"

unsafe_printer_fixture="$test_tmp/unsafe-printer-root"
mkdir -p "$unsafe_printer_fixture/etc/cups"
cat >"$unsafe_printer_fixture/etc/cups/printers.conf" <<'EOF'
<Printer Remote>
DeviceURI implicitclass://Remote/
</Printer>
EOF
: >"$printer_log"
if (retire_factory_printer_discovery \
  "$unsafe_printer_fixture" "$test_tmp/pacman") >/dev/null 2>&1; then
  echo "factory reset accepted an offline generated queue" >&2
  exit 1
fi
[[ ! -s $printer_log ]]
[[ ! -e $unsafe_printer_fixture/var/lib/monarch/reconcile/cups-browsed-removed ]]

query_error_fixture="$test_tmp/query-error-printer-root"
query_error_log="$test_tmp/query-error-pacman.log"
mkdir -p "$query_error_fixture/etc/systemd/system/multi-user.target.wants"
ln -s /usr/lib/systemd/system/cups-browsed.service \
  "$query_error_fixture/etc/systemd/system/multi-user.target.wants/cups-browsed.service"
cat >"$test_tmp/pacman-query-error" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_PACMAN_LOG"
echo 'error: database is inconsistent' >&2
exit 1
EOF
chmod +x "$test_tmp/pacman-query-error"

export TEST_PACMAN_LOG="$query_error_log"
if (retire_factory_printer_discovery \
  "$query_error_fixture" "$test_tmp/pacman-query-error") >/dev/null 2>&1; then
  echo "factory reset treated a package database error as package absence" >&2
  exit 1
fi
[[ ! -e $query_error_fixture/var/lib/monarch/reconcile/cups-browsed-removed ]]

echo "factory reset ESP preservation: ok"
