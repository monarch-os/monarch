#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_success() {
  local description=$1
  shift
  "$@" >/dev/null || fail "$description"
  pass "$description"
}

assert_failure() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$description"
  fi
  pass "$description"
}

mkdir -p "$TMP/bin" "$TMP/video" "$TMP/usb/1-1" "$TMP/config/niri"

cat >"$TMP/bin/v4l2-ctl" <<'EOF'
#!/bin/bash
[[ $* == *video-capture* ]] && printf 'Device Caps :\n\tVideo Capture\n'
EOF
chmod +x "$TMP/bin/v4l2-ctl"
touch "$TMP/video/video-capture"

PATH="$TMP/bin:$PATH" MONARCH_VIDEO_DEVICES_PATH="$TMP/video" \
  assert_success "detects a capture-capable webcam" "$ROOT/bin/monarch-hw-webcam"
assert_failure "reports no webcam when no video device exists" \
  env MONARCH_VIDEO_DEVICES_PATH="$TMP/empty-video" "$ROOT/bin/monarch-hw-webcam"

printf '27c6\n' >"$TMP/usb/1-1/idVendor"
MONARCH_USB_DEVICES_PATH="$TMP/usb" \
  assert_success "detects a supported fingerprint vendor" "$ROOT/bin/monarch-hw-fingerprint"
mkdir -p "$TMP/usb/1-1/1-1:1.0/driver"
MONARCH_USB_DEVICES_PATH="$TMP/usb" \
  assert_failure "rejects a vendor device bound to a kernel driver" "$ROOT/bin/monarch-hw-fingerprint"
printf 'Generic Biometric Reader\n' >"$TMP/usb/1-1/product"
MONARCH_USB_DEVICES_PATH="$TMP/usb" \
  assert_success "trusts an explicit biometric product name" "$ROOT/bin/monarch-hw-fingerprint"

cat >"$TMP/bin/monarch-hw-touchpad" <<'EOF'
#!/bin/bash
printf 'Test Touchpad\n'
EOF
cat >"$TMP/bin/monarch-hw-touchscreen" <<'EOF'
#!/bin/bash
printf 'Test Touchscreen\n'
EOF
chmod +x "$TMP/bin/monarch-hw-touchpad" "$TMP/bin/monarch-hw-touchscreen"

status=$(PATH="$TMP/bin:$ROOT/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" \
  "$ROOT/bin/monarch-toggle-touchpad" status)
[[ $(jq -r '.enabled' <<<"$status") == true ]] || fail "touchpad starts enabled"
pass "touchpad starts enabled"

cat >"$TMP/config/niri/runtime.kdl" <<'EOF'
input {
  touchpad {
    off
  }
  touch {
    off
  }
}
EOF

for device in touchpad touchscreen; do
  status=$(PATH="$TMP/bin:$ROOT/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" \
    "$ROOT/bin/monarch-toggle-$device" status)
  [[ $(jq -r '.enabled' <<<"$status") == false ]] || fail "$device reports its disabled state"
  pass "$device reports its disabled state"
done
