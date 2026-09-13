#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
log="$test_tmp/packages"
mkdir -p "$fake_bin"

cat >"$fake_bin/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "${PCI_INFO:-}"
STUB

cat >"$fake_bin/monarch-hw-kernel-headers" <<'STUB'
#!/bin/bash
printf '%s\n' linux-cachyos-headers linux-lts-headers
STUB

cat >"$fake_bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_LOG"
STUB

chmod +x "$fake_bin/lspci" "$fake_bin/monarch-hw-kernel-headers" \
  "$fake_bin/monarch-pkg-add"

run_fix() {
  PATH="$fake_bin:/usr/bin" PACKAGE_LOG="$log" PCI_INFO="$1" \
    bash "$ROOT/install/hardware/fix-bcm43xx.sh"
}

run_fix '03:00.0 Network controller [0280]: Broadcom Inc. BCM4360 [14e4:43a0]'
[[ $(<"$log") == "broadcom-wl-dkms dkms linux-cachyos-headers linux-lts-headers" ]] ||
  fail "Broadcom driver does not use DKMS with every installed kernel header" "$(<"$log")"
pass "supported Broadcom chips use DKMS with every installed kernel header"

: >"$log"
run_fix '03:00.0 Network controller [0280]: Intel Corporation Wi-Fi [8086:2725]'
[[ ! -s $log ]] || fail "an unsupported Wi-Fi device installed Broadcom packages"
pass "unsupported Wi-Fi devices do not install Broadcom packages"
