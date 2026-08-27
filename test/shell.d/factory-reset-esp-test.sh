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
reset_limine_config "$fixture" /boot "$old_id" "$preserved"

grep -q '^/Windows' "$preserved"
grep -q "machine-id=$foreign_id" "$preserved"
! grep -q "machine-id=$old_id" "$preserved"
! grep -q '^/EFI fallback' "$preserved"
[[ -f $fixture/boot/$foreign_id/foreign ]]
[[ ! -e $fixture/boot/$old_id ]]
grep -q '^interface_branding: Monarch$' "$fixture/boot/limine.conf"

echo "factory reset ESP preservation: ok"
