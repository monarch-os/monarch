#!/bin/bash

# Exercises the Wi-Fi QR payload — escaping, the security types, interface
# detection and the meta line the Noctalia panel parses — against a fake nmcli,
# so none of it needs a wireless card, a connection, or polkit.
#
# The commands under test prepend their own bin/ to PATH, so a stub named after a
# Monarch command would never be reached: monarch-wifi-device is the real one
# here, driven by the fake ip/nmcli underneath it.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
QR="$ROOT/bin/monarch-wifi-qr"
WIFI_PASSWORD="$ROOT/bin/monarch-wifi-password"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/run"

# The PNG mode writes under XDG_RUNTIME_DIR; keep it inside the sandbox.
export XDG_RUNTIME_DIR="$TMP/run"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"

  if [[ $actual != "$expected" ]]; then
    fail "$description" "Expected: $expected" "Actual:   $actual"
  fi

  pass "$description"
}

cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
if [[ $* == *"DEVICE,TYPE,STATE"* ]]; then
  printf 'eth0:ethernet:connected\nwlan0:wifi:connected\n'
elif [[ $* == *GENERAL.CON-UUID* ]]; then
  echo test-uuid
else
  printf '%s' "$QR_NMCLI_FIELDS"
fi
STUB

# No default route in the sandbox, so detection falls through to nmcli's device
# list — the path a wired-plus-wireless machine takes anyway.
cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
exit 1
STUB

# Records what it was fed and refuses to be handed the payload as an argument:
# that is how the password would end up in /proc/<pid>/cmdline.
cat >"$TMP/bin/qrencode" <<'STUB'
#!/bin/bash
output="-"
args=("$@")
for index in "${!args[@]}"; do
  [[ ${args[index]} != WIFI:* ]] || exit 97
  [[ ${args[index]} != "--output" ]] || output=${args[index + 1]}
done

payload=$(cat)
printf '%s' "$payload" >"$QR_PAYLOAD_FILE"

if [[ $output == "-" ]]; then
  printf 'QR\n'
else
  printf 'PNG' >"$output"
fi
STUB

chmod +x "$TMP/bin/nmcli" "$TMP/bin/ip" "$TMP/bin/qrencode"
export PATH="$TMP/bin:$PATH"
export QR_PAYLOAD_FILE="$TMP/payload"

run_qr() {
  QR_NMCLI_FIELDS=$1 "$QR" "${@:2}"
}

assert_payload() {
  local description="$1" fields="$2" expected="$3"
  shift 3

  rm -f "$QR_PAYLOAD_FILE"
  run_qr "$fields" --payload "$@" >"$TMP/out"
  assert_equals "$description" "$(<"$TMP/out")" "$expected"
}

# ── The payload ──────────────────────────────────────────────────────────────

assert_payload \
  "escapes the separators a WIFI: URI reserves" \
  $'Cafe;Guest\\5G\nwpa-psk\np,a:ss;word\\42\nno\n' \
  'WIFI:T:WPA;S:Cafe\;Guest\\5G;P:p\,a\:ss\;word\\42;;' \
  wlan0

assert_payload \
  "encodes an open network as nopass" \
  $'Cafe Open\nnone\n\nno\n' \
  'WIFI:T:nopass;S:Cafe Open;P:;;' \
  wlan0

assert_payload \
  "marks a hidden network" \
  $'Hidden Network\nwpa-psk\nsecret\nyes\n' \
  'WIFI:T:WPA;S:Hidden Network;P:secret;H:true;;' \
  wlan0

# NetworkManager models WEP as key-mgmt "none" plus a wep-key, which must not be
# mistaken for an open network: the QR would scan and fail to join.
assert_payload \
  "encodes a WEP network as WEP, not as open" \
  $'Old Router\nnone\n\nno\nwep-secret\n' \
  'WIFI:T:WEP;S:Old Router;P:wep-secret;;' \
  wlan0

assert_payload \
  "detects the Wi-Fi interface when none is given" \
  $'Cafe Detected\nwpa-psk\nsecret\nno\n' \
  'WIFI:T:WPA;S:Cafe Detected;P:secret;;'

# ── The panel's meta line ────────────────────────────────────────────────────

rm -f "$QR_PAYLOAD_FILE"
meta=$(run_qr $'Cafe Detected\nwpa-psk\nsecret\nno\n' --png)
IFS=$'\t' read -r tag device security png ssid <<<"$meta"

assert_equals "the meta line leads with the tag" "$tag" "meta"
assert_equals "the meta line names the interface it shared" "$device" "wlan0"
assert_equals "the meta line names the security type" "$security" "WPA"
assert_equals "the meta line ends with the SSID" "$ssid" "Cafe Detected"
assert_equals "the payload reaches qrencode over the pipe" "$(<"$QR_PAYLOAD_FILE")" \
  'WIFI:T:WPA;S:Cafe Detected;P:secret;;'
[[ -f $png ]] || fail "the meta line points at a written PNG" "missing: $png"
pass "the meta line points at a written PNG"
[[ $png == "$XDG_RUNTIME_DIR/monarch/"* ]] || fail "the PNG is written under the runtime dir" "actual: $png"
pass "the PNG is written under the runtime dir"

# A second run replaces the first: the file left behind carries the previous
# network's password, and the shell caches textures by path.
stale=$png
meta=$(run_qr $'Other Network\nwpa-psk\nsecret\nno\n' --png)
png=$(cut -f4 <<<"$meta")
[[ ! -f $stale ]] || fail "a new code prunes the previous PNG" "still there: $stale"
pass "a new code prunes the previous PNG"
[[ $png != "$stale" ]] || fail "a new code takes a fresh filename" "reused: $png"
pass "a new code takes a fresh filename"

# ── What cannot be shared ────────────────────────────────────────────────────

rm -f "$QR_PAYLOAD_FILE"
if run_qr $'Enterprise\nwpa-eap\nsecret\nno\n' --payload wlan0 >"$TMP/out" 2>"$TMP/err"; then
  fail "enterprise Wi-Fi is refused" "the command unexpectedly succeeded"
fi
assert_equals "enterprise Wi-Fi is refused" "$(<"$TMP/err")" \
  "Enterprise Wi-Fi has no shareable password"
[[ ! -e $QR_PAYLOAD_FILE ]] || fail "enterprise Wi-Fi never reaches qrencode" "qrencode ran"
pass "enterprise Wi-Fi never reaches qrencode"

# ── The reveal ───────────────────────────────────────────────────────────────

password=$(QR_NMCLI_FIELDS=$'Cafe\nwpa-psk\nsecret\nno\n' "$WIFI_PASSWORD" wlan0)
assert_equals "the password command prints the PSK" "$password" "secret"

password=$(QR_NMCLI_FIELDS=$'Cafe\nnone\n\nno\nwep-secret\n' "$WIFI_PASSWORD" wlan0)
assert_equals "the password command reads a WEP key" "$password" "wep-secret"

if QR_NMCLI_FIELDS=$'Cafe\nwpa-eap\nsecret\nno\n' "$WIFI_PASSWORD" wlan0 >"$TMP/out" 2>"$TMP/err"; then
  fail "the password command refuses enterprise Wi-Fi" "the command unexpectedly succeeded"
fi
assert_equals "the password command refuses enterprise Wi-Fi" "$(<"$TMP/err")" \
  "Enterprise Wi-Fi has no shareable password"

if QR_NMCLI_FIELDS=$'Cafe\nnone\n\nno\n' "$WIFI_PASSWORD" wlan0 >"$TMP/out" 2>"$TMP/err"; then
  fail "the password command refuses an open network" "the command unexpectedly succeeded"
fi
assert_equals "the password command refuses an open network" "$(<"$TMP/err")" \
  "This network has no password"
