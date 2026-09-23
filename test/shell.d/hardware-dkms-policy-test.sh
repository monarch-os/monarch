#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
vendor="$test_tmp/sys_vendor"
modprobe_dir="$test_tmp/modprobe.d"
modules="$test_tmp/modules"
package_log="$test_tmp/packages"
mkdir -p "$fake_bin" "$modules/7.2.0/extra"

cat >"$fake_bin/monarch-hw-kernel-headers" <<'STUB'
#!/bin/bash
printf '%s\n' linux-cachyos-headers linux-cachyos-lts-headers
STUB

cat >"$fake_bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_LOG"
STUB

cat >"$fake_bin/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "${PCI_INFO:-}"
STUB

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$T2_LOG"
if [[ $1 == "tee" ]]; then
  target="$T2_ROOT$2"
  /usr/bin/mkdir -p "${target%/*}"
  /usr/bin/tee "$target"
fi
STUB

chmod +x "$fake_bin/monarch-hw-kernel-headers" "$fake_bin/monarch-pkg-add" \
  "$fake_bin/lspci" "$fake_bin/sudo"

run_tuxedo_fix() {
  MONARCH_DMI_VENDOR_PATH="$vendor" \
    MONARCH_MODPROBE_DIR="$modprobe_dir" \
    MONARCH_MODULES_PATH="$modules" \
    PACKAGE_LOG="$package_log" \
    PATH="$fake_bin:/usr/bin" \
    bash "$ROOT/install/hardware/fix-tuxedo-backlight.sh"
}

printf '%s\n' "TUXEDO Computers GmbH" >"$vendor"
touch "$modules/7.2.0/extra/clevo-xsm-wmi.ko"
run_tuxedo_fix

expected="linux-cachyos-headers linux-cachyos-lts-headers tuxedo-drivers-nocompatcheck-dkms"
[[ $(<"$package_log") == "$expected" ]] ||
  fail "Tuxedo driver did not use every installed kernel header" "$(<"$package_log")"
[[ $(<"$modprobe_dir/blacklist-clevo-xsm-wmi.conf") == "blacklist clevo_xsm_wmi" ]] ||
  fail "Tuxedo driver did not blacklist the conflicting module"
[[ ! -e $modules/7.2.0/extra/clevo-xsm-wmi.ko ]] ||
  fail "Tuxedo driver kept an orphaned conflicting module"
pass "Tuxedo driver follows the installed-kernel header policy"

: >"$package_log"
printf '%s\n' "Framework" >"$vendor"
run_tuxedo_fix
[[ ! -s $package_log ]] || fail "non-Tuxedo hardware installed Tuxedo drivers"
pass "non-Tuxedo hardware skips the Tuxedo driver"

[[ ! -e $ROOT/install/hardware/fix-yt6801-ethernet-adapter.sh ]] ||
  fail "obsolete YT6801 DKMS leaf still exists"
! grep -qF 'fix-yt6801-ethernet-adapter.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware installer still calls the obsolete YT6801 DKMS leaf"
pass "YT6801 uses the kernel's in-tree dwmac-motorcomm driver"

grep -qxF linux-cachyos-headers "$ROOT/install/monarch-base.packages" ||
  fail "fresh installs omit the CachyOS kernel headers"
! grep -qxF linux-headers "$ROOT/install/monarch-base.packages" ||
  fail "fresh installs include headers for the absent stock Arch kernel"
! grep -qxF linux-cachyos-headers "$ROOT/install/monarch-other.packages" ||
  fail "CachyOS kernel headers remain mirror-only"
pass "fresh installs require only the selected kernel headers"

t2_fix="$ROOT/install/hardware/apple/fix-t2.sh"
: >"$package_log"
t2_root="$test_tmp/t2-root"
t2_log="$test_tmp/t2-actions"
PCI_INFO='00:1f.0 System peripheral [0880]: Apple Inc. T2 [106b:1801]' \
  PACKAGE_LOG="$package_log" T2_LOG="$t2_log" T2_ROOT="$t2_root" USER=tester \
  PATH="$fake_bin:/usr/bin" bash "$t2_fix" >/dev/null
[[ $(<"$package_log") == "apple-t2-audio-config t2fanrd tiny-dfr" ]] ||
  fail "T2 setup requested packages outside the signed offline mirror" "$(<"$package_log")"
grep -qxF 'MODULES+=(apple-bce? t2bce_dma? t2bce_core? t2bce_vhci? usbhid hid_apple hid_generic xhci_pci xhci_hcd)' \
  "$t2_root/etc/mkinitcpio.conf.d/apple-t2.conf" || fail "T2 initramfs modules are incomplete"
grep -qxF 'KERNEL_CMDLINE[default]+=" intel_iommu=on iommu=pt pm_async=off pcie_ports=compat"' \
  "$t2_root/etc/limine-entry-tool.d/t2-mac.conf" || fail "T2 kernel parameters are incomplete"
grep -qxF 'systemctl enable tiny-dfr.service' "$t2_log" || fail "T2 touch bar service is not enabled"

! grep -qE 'linux-t2|apple-bcm-firmware[[:space:]]*\\' "$t2_fix" ||
  fail "T2 setup installs packages absent from Monarch's offline mirror"
grep -qF 'apple-bce? t2bce_dma? t2bce_core? t2bce_vhci?' "$t2_fix" ||
  fail "T2 initramfs does not bridge the Linux 7.2 BCE module transition"
grep -qF 'pm_async=off' "$t2_fix" || fail "T2 kernel parameters omit synchronous power management"
expected_order='BOOT_ORDER="linux-cachyos, linux-cachyos-*, *, *fallback, Snapshots"'
grep -qxF "$expected_order" "$ROOT/etc/limine-entry-tool.d/monarch-defaults.conf" ||
  fail "packaged Limine defaults do not prefer linux-cachyos"
grep -qxF "$expected_order" "$ROOT/default/limine/default.conf" ||
  fail "installer Limine defaults do not prefer linux-cachyos"
pass "T2 support stays on CachyOS across the Linux 7.2 module transition"
