#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
empty_bin="$tmp_dir/empty-bin"
mkdir -p "$empty_bin"

write_pci_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0 spec slot ids
  for spec in "$@"; do
    slot=$(printf '0000:%02x:00.0' "$index")
    mkdir -p "$tmp_dir/devices/$slot"
    printf '%s\n' "${spec%%:*}" >"$tmp_dir/devices/$slot/vendor"
    ids=${spec#*:}
    printf '%s\n' "${ids%%:*}" >"$tmp_dir/devices/$slot/device"
    printf '%s\n' "${spec##*:}" >"$tmp_dir/devices/$slot/class"
    ((index += 1))
  done
}

hw_nvidia() {
  PATH="$empty_bin" MONARCH_PCI_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/monarch-hw-$1"
}

assert_detection() {
  local description=$1 nvidia=$2 gsp=$3 without_gsp=$4 command detector expected actual

  for command in nvidia gsp without-gsp; do
    case $command in
    nvidia) expected=$nvidia ;;
    gsp) expected=$gsp ;;
    without-gsp) expected=$without_gsp ;;
    esac

    detector=nvidia
    [[ $command == "nvidia" ]] || detector="nvidia-$command"
    actual=no
    hw_nvidia "$detector" && actual=yes
    [[ $actual == "$expected" ]] ||
      fail "$description" "monarch-hw-$detector: expected $expected, got $actual"
  done

  pass "$description"
}

write_pci_devices 0x1002:0x15e7:0x030000
assert_detection "AMD graphics do not match NVIDIA detectors" no no no

write_pci_devices 0x1002:0x15e7:0x030000 0x10de:0x2560:0x030200
assert_detection "Ampere is detected without reading PCI config space" yes yes no

write_pci_devices 0x10de:0x1e00:0x030000
assert_detection "Turing starts the GSP range" yes yes no

write_pci_devices 0x10de:0x1d81:0x030000
assert_detection "Volta ends the non-GSP range" yes no yes

write_pci_devices 0x10de:0x1340:0x030000
assert_detection "Maxwell starts the supported non-GSP range" yes no yes

write_pci_devices 0x10de:0x1004:0x030000
assert_detection "Kepler is detected but excluded from supported drivers" yes no no

write_pci_devices 0x10de:0x228e:0x040300
assert_detection "NVIDIA audio functions are not GPUs" no no no

write_pci_devices
assert_detection "an empty PCI tree detects no NVIDIA GPU" no no no

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/monarch-cmd-present" <<'STUB'
#!/bin/bash
[[ $1 == "supergfxctl" ]]
STUB

cat >"$empty_bin/monarch-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash

[[ $1 == "-s" ]] || exit 64

case ${BLOCKED:-no} in
kill-only)
  trap '' TERM
  /usr/bin/sleep 30
  ;;
term)
  /usr/bin/sleep 30
  ;;
esac

(( ${FAIL_STATUS:-0} == 0 )) || exit "$FAIL_STATUS"
printf '%s\n' "${SUPPORTED_MODES:-Integrated Hybrid}"
STUB
chmod +x "$fake_bin/monarch-cmd-present" "$fake_bin/supergfxctl" \
  "$empty_bin/monarch-cmd-present"

hybrid_gpu() {
  PATH="$fake_bin:/usr/bin" MONARCH_PCI_DEVICES_PATH="$tmp_dir/devices" \
    timeout --kill-after=1s 5s "$ROOT/bin/monarch-hw-hybrid-gpu"
}

no_supergfx_hybrid_gpu() {
  PATH="$empty_bin" MONARCH_PCI_DEVICES_PATH="$tmp_dir/devices" \
    "$ROOT/bin/monarch-hw-hybrid-gpu"
}

write_pci_devices 0x1002:0x15e7:0x030000 0x10de:0x2560:0x030200
no_supergfx_hybrid_gpu || fail "hybrid detection counts sysfs display devices without supergfxctl"
pass "hybrid detection counts sysfs display devices without supergfxctl"

write_pci_devices 0x1002:0x15e7:0x030000
no_supergfx_hybrid_gpu && fail "hybrid detection rejects one sysfs display device"
pass "hybrid detection rejects one sysfs display device"

hybrid_gpu || fail "hybrid detection accepts supergfxctl Hybrid mode"
pass "hybrid detection accepts supergfxctl Hybrid mode"

SUPPORTED_MODES="Integrated Vfio" hybrid_gpu &&
  fail "hybrid detection rejects supergfxctl without Hybrid mode"
pass "hybrid detection rejects supergfxctl without Hybrid mode"

write_pci_devices 0x1002:0x15e7:0x030000 0x10de:0x2560:0x030200
FAIL_STATUS=2 hybrid_gpu &&
  fail "hybrid detection must not fall back after an ordinary supergfxctl failure"
pass "hybrid detection trusts an ordinary supergfxctl failure"

BLOCKED=term hybrid_gpu ||
  fail "hybrid detection falls back after a terminated supergfxctl query"
pass "hybrid detection falls back after a terminated supergfxctl query"

write_pci_devices 0x1002:0x15e7:0x030000
BLOCKED=kill-only hybrid_gpu &&
  fail "hybrid detection rejects one GPU after killing a wedged supergfxctl query"
pass "hybrid detection kills a wedged supergfxctl query and falls back"

nvidia_bin="$tmp_dir/nvidia-bin"
nvidia_home="$tmp_dir/nvidia-home"
nvidia_packages="$tmp_dir/nvidia-packages"
mkdir -p "$nvidia_bin" "$nvidia_home"

cat >"$nvidia_bin/monarch-hw-nvidia" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$nvidia_bin/monarch-hw-nvidia-gsp" <<'STUB'
#!/bin/bash
[[ $NVIDIA_TEST_MODE == "gsp" ]]
STUB
cat >"$nvidia_bin/monarch-hw-nvidia-without-gsp" <<'STUB'
#!/bin/bash
[[ $NVIDIA_TEST_MODE == "legacy" ]]
STUB
cat >"$nvidia_bin/monarch-hw-kernel-headers" <<'STUB'
#!/bin/bash
printf '%s\n' linux-cachyos-headers
STUB
cat >"$nvidia_bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$NVIDIA_PACKAGES_LOG"
STUB
cat >"$nvidia_bin/lspci" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$nvidia_bin/sudo" <<'STUB'
#!/bin/bash
[[ $1 == "tee" ]] || exit 64
cat >/dev/null
STUB
chmod +x "$nvidia_bin"/*

run_nvidia_installer() {
  local mode=$1

  NVIDIA_TEST_MODE="$mode" NVIDIA_PACKAGES_LOG="$nvidia_packages" \
    HOME="$nvidia_home" MONARCH_INSTALL=1 PATH="$nvidia_bin:/usr/bin" \
    "$ROOT/bin/monarch-install-nvidia"
}

run_gaming_driver_installer() {
  local mode=$1

  NVIDIA_TEST_MODE="$mode" NVIDIA_PACKAGES_LOG="$nvidia_packages" \
    PATH="$nvidia_bin:/usr/bin" "$ROOT/bin/monarch-install-gaming-gpu-lib32" \
    >/dev/null
}

run_nvidia_installer gsp
[[ $(paste -sd ' ' "$nvidia_packages") == "linux-cachyos-headers nvidia-open-dkms nvidia-utils libva-nvidia-driver" ]] ||
  fail "the current NVIDIA driver install excludes gaming libraries"
pass "the current NVIDIA driver install excludes gaming libraries"

run_nvidia_installer legacy
[[ $(paste -sd ' ' "$nvidia_packages") == "linux-cachyos-headers nvidia-580xx-dkms nvidia-580xx-utils" ]] ||
  fail "the legacy NVIDIA driver install excludes gaming libraries"
pass "the legacy NVIDIA driver install excludes gaming libraries"

run_gaming_driver_installer gsp
[[ $(<"$nvidia_packages") == "lib32-nvidia-utils" ]] ||
  fail "gaming installs current NVIDIA 32-bit libraries"
pass "gaming installs current NVIDIA 32-bit libraries"

run_gaming_driver_installer legacy
[[ $(<"$nvidia_packages") == "lib32-nvidia-580xx-utils" ]] ||
  fail "gaming installs legacy NVIDIA 32-bit libraries"
pass "gaming installs legacy NVIDIA 32-bit libraries"

if grep -Eq '^[^#[:space:]]*lib32-nvidia' "$ROOT/install/monarch-other.packages"; then
  fail "the offline ISO excludes NVIDIA gaming libraries"
fi
pass "the offline ISO excludes NVIDIA gaming libraries"
