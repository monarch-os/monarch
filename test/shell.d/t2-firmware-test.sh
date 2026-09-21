#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

setup_command="$ROOT/bin/monarch-setup-t2-firmware"
grep -qF 't2linux/wiki/5e79e6ed1481571df10d86c13ee35d5cbf5ef1ec/docs/tools/firmware.sh' \
  "$setup_command" || fail "macOS preparation does not pin the t2linux source"
grep -qF 'c1c1d8aa25bb5f089e46ccd0d9738fc13bfbd784f499aa924466c690f059961e' \
  "$setup_command" || fail "macOS preparation omits the t2linux source checksum"
pass "macOS preparation pins and verifies the t2linux tool"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

raw_tree="$test_tmp/raw"
mkdir -p "$raw_tree/wifi/C-4377__s-B3" "$raw_tree/bluetooth"
printf 'wifi-binary\n' >"$raw_tree/wifi/C-4377__s-B3/tahiti-X0.trx"
printf ' boardrev =0x1101\n' >"$raw_tree/wifi/C-4377__s-B3/P-tahiti-X0.txt"
printf 'wifi-binary-alt\n' >"$raw_tree/wifi/C-4377__s-B3/tahiti-X1.trx"
printf ' boardrev =0x1102\n' >"$raw_tree/wifi/C-4377__s-B3/P-tahiti-X1.txt"
printf 'bluetooth-binary\n' >"$raw_tree/bluetooth/BCM4377B3_PCIE_macOS_Tahiti_MUR.bin"
printf 'bluetooth-parameters\n' >"$raw_tree/bluetooth/BCM4377B3_PCIE_macOS_Tahiti_MUR.ptb"

raw_archive="$test_tmp/firmware-raw.tar.gz"
tar -czf "$raw_archive" -C "$raw_tree" .

normalizer="$ROOT/assets/t2/firmware.py"
python "$normalizer" verify "$raw_archive" | grep -qF '4 Wi-Fi and 2 Bluetooth files'
normalized="$test_tmp/firmware.tar"
python "$normalizer" normalize "$raw_archive" "$normalized" >/dev/null

for firmware in \
  brcmfmac4377b3-pcie.apple,tahiti-X0.bin \
  brcmfmac4377b3-pcie.apple,tahiti-X0.txt \
  brcmfmac4377b3-pcie.apple,tahiti-X1.bin \
  brcmfmac4377b3-pcie.apple,tahiti-X1.txt \
  brcmbt4377b3-apple,tahiti-m.bin \
  brcmbt4377b3-apple,tahiti-m.ptb; do
  bsdtar -tf "$normalized" | grep -qxF "$firmware" ||
    fail "normalizer omitted $firmware"
done
[[ $(bsdtar -xOf "$normalized" brcmfmac4377b3-pcie.apple,tahiti-X0.txt) == "boardrev=0x1101" ]] ||
  fail "normalizer did not clean the NVRAM key"
pass "t2linux firmware is normalized without executing the EFI script"

package="$test_tmp/apple-bcm-firmware-local-1-1-any.pkg.tar.zst"
MONARCH_PATH="$ROOT" MONARCH_T2_FIRMWARE_NORMALIZER="$normalizer" \
  "$setup_command" build "$raw_archive" "$package" >/dev/null

pacman -Qip "$package" | grep -qE '^Name[[:space:]]*: apple-bcm-firmware-local$' ||
  fail "local firmware package has the wrong name"
pacman -Qip "$package" | grep -qE '^Provides[[:space:]]*: apple-bcm-firmware$' ||
  fail "local firmware package does not satisfy apple-bcm-firmware"
bsdtar -tf "$package" | grep -qxF 'usr/lib/firmware/brcm/brcmfmac4377b3-pcie.apple,tahiti-X0.bin' ||
  fail "local firmware package omits the Wi-Fi payload"
pass "normalized firmware becomes a locally owned pacman package"

esp="$test_tmp/esp"
staged="$test_tmp/staged/firmware-raw.tar.gz"
mkdir -p "$esp"
cp "$raw_archive" "$esp/firmware-raw.tar.gz"
MONARCH_PATH="$ROOT" MONARCH_T2_FIRMWARE_NORMALIZER="$normalizer" \
  MONARCH_T2_FIRMWARE_ESP_ROOT="$esp" \
  "$setup_command" stage /dev/nvme0n1 "$staged" >/dev/null
cmp -s "$raw_archive" "$staged" || fail "EFI firmware archive changed while staging"
[[ $(stat -c %a "$staged") == "600" ]] || fail "staged firmware archive is not private"
pass "prepared EFI firmware is copied before disk changes"

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/lsblk" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"blockdevices":[{"path":"/dev/nvme0n1","type":"disk","fstype":null,"parttype":null,"pkname":null,"children":[{"path":"/dev/nvme0n1p1","type":"part","fstype":null,"parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","pkname":"/dev/nvme0n1"}]}]}
JSON
EOF
cat >"$fake_bin/findmnt" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$fake_bin/mount" <<'EOF'
#!/bin/bash
cp "$FAKE_ESP/firmware-raw.tar.gz" "${@: -1}/firmware-raw.tar.gz"
EOF
cat >"$fake_bin/umount" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"$UMOUNT_LOG"
rm -f "$1/firmware-raw.tar.gz"
EOF
chmod +x "$fake_bin/lsblk" "$fake_bin/findmnt" "$fake_bin/mount" "$fake_bin/umount"

mounted_stage="$test_tmp/mounted-stage/firmware-raw.tar.gz"
FAKE_ESP="$esp" UMOUNT_LOG="$test_tmp/unmounted" PATH="$fake_bin:/usr/bin" \
  MONARCH_PATH="$ROOT" MONARCH_T2_FIRMWARE_NORMALIZER="$normalizer" \
  MONARCH_T2_FIRMWARE_ALLOW_UNPRIVILEGED=1 \
  "$setup_command" stage /dev/nvme0n1 "$mounted_stage" >/dev/null
cmp -s "$raw_archive" "$mounted_stage" || fail "staging from a mounted ESP changed the archive"
[[ -s $test_tmp/unmounted ]] || fail "temporary EFI mount was not released"
pass "EFI discovery preserves empty lsblk fields and unmounts temporary mounts"

empty="$test_tmp/empty.tar.gz"
tar -czf "$empty" --files-from /dev/null
if python "$normalizer" verify "$empty" >/dev/null 2>&1; then
  fail "normalizer accepted an archive without T2 Wi-Fi firmware"
fi
pass "invalid EFI firmware archives are rejected"
