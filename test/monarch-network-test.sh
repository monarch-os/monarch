#!/bin/bash

# Exercises the commands the network panel reads and drives — the status shapes,
# the network list, and the four actions — against fake nmcli/ip/iw, so none of
# it needs a card, a route or polkit.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATUS="$ROOT/bin/monarch-network-status"
LIST="$ROOT/bin/monarch-wifi-list"
JOIN="$ROOT/bin/monarch-wifi-join"
FORGET="$ROOT/bin/monarch-wifi-forget"
RADIO="$ROOT/bin/monarch-toggle-wifi"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sys/wlan0/wireless" "$TMP/sys/eth0"

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"
  [[ $actual == "$expected" ]] || fail "$description" "Expected: $expected" "Actual:   $actual"
  pass "$description"
}

# `ip route get` names the device; the rest of the fake answers whatever the
# environment says, so one stub serves every case.
cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
case "$*" in
  *"-j route get"*) printf '%s' "$IP_ROUTE_JSON" ;;
  *"route get"*)    [[ -n $IP_DEV ]] && printf 'x via y dev %s src z\n' "$IP_DEV" ;;
  *"-j addr show"*) printf '%s' "$IP_ADDR_JSON" ;;
esac
STUB

cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NM_CALLS"
case "$*" in
  *"GENERAL.STATE,GENERAL.CONNECTION dev show"*)
    printf 'GENERAL.STATE:%s\nGENERAL.CONNECTION:%s\n' "$NM_STATE" "$NM_CONN" ;;
  *"IN-USE,SIGNAL dev wifi list"*) printf '*:%s\n' "$NM_SIGNAL" ;;
  *"IN-USE,SIGNAL,SECURITY,SSID dev wifi list"*) printf '%s' "$NM_SCAN" ;;
  *"DEVICE,TYPE device status"*) printf 'wlan0:wifi\n' ;;
  *"DEVICE,TYPE,STATE device status"*) printf 'wlan0:wifi:connected\n' ;;
  *"-g NAME connection show"*) printf '%s' "$NM_SAVED" ;;
  *"radio wifi off"*|*"radio wifi on"*) : ;;
  *"radio wifi"*) printf '%s\n' "${NM_RADIO:-enabled}" ;;
  *"device wifi connect"*) exit "${NM_JOIN_STATUS:-0}" ;;
  *"connection delete"*) exit "${NM_DELETE_STATUS:-0}" ;;
esac
STUB

cat >"$TMP/bin/iw" <<'STUB'
#!/bin/bash
printf 'Connected to 00:11 (on wlan0)\n\tSSID: %s\n\tfreq: %s\n\tsignal: -42 dBm\n\ttx bitrate: 130.0 MBit/s\n' \
  "$IW_SSID" "$IW_FREQ"
STUB

printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/ping"
chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export NM_CALLS="$TMP/calls"
: >"$NM_CALLS"

# monarch-network-status reads /sys to tell wireless from wired; point it at a
# tree the test owns by running from a fake root is not possible, so the wired
# case is driven by a device name with no wireless directory under the real /sys.
export IP_DEV="" NM_STATE="100 (connected)" NM_CONN="Cafe" NM_SIGNAL="72"
export IW_SSID="Cafe" IW_FREQ="5745.0"

# ── The pill line ────────────────────────────────────────────────────────────

assert_equals "no route reports disconnected" \
  "$("$STATUS" | cat -A | head -1)" 'disconnected^I^I^I$'

# ── The verbose block ────────────────────────────────────────────────────────

export IP_ROUTE_JSON='[{"dev":"eth0","gateway":"192.168.1.1","prefsrc":"192.168.1.50"}]'
export IP_ADDR_JSON='[{"addr_info":[{"family":"inet","prefixlen":24}]}]'
export MONARCH_RESOLVED_CONF="$TMP/resolved.conf"

printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1\n' >"$MONARCH_RESOLVED_CONF"
verbose=$("$STATUS" --verbose)
assert_equals "recognises the Cloudflare profile" \
  "$(awk '$1=="dns" {print $2}' <<<"$verbose")" "Cloudflare"
assert_equals "reports the address" \
  "$(awk '$1=="ip" {print $2}' <<<"$verbose")" "192.168.1.50"
assert_equals "reports the prefix" \
  "$(awk '$1=="prefix" {print $2}' <<<"$verbose")" "24"

printf '[Resolve]\nDNSOverTLS=no\n' >"$MONARCH_RESOLVED_CONF"
assert_equals "a file with no DNS= is DHCP" \
  "$("$STATUS" --verbose | awk '$1=="dns" {print $2}')" "DHCP"

printf '[Resolve]\nDNS=192.168.1.1\n' >"$MONARCH_RESOLVED_CONF"
assert_equals "anything else is Custom" \
  "$("$STATUS" --verbose | awk '$1=="dns" {print $2}')" "Custom"

# ── The network list ─────────────────────────────────────────────────────────

export NM_SAVED=$'Cafe\nHome\n'
export NM_SCAN=$'*:90:WPA2:Cafe\n:70:WPA2:Home\n:55::Open Net\n:40:WPA2:Cafe\n'

list=$("$LIST")
assert_equals "marks the network in use" \
  "$(awk -F'\t' '$5=="Cafe" {print $3}' <<<"$list")" "yes"
assert_equals "marks a saved network" \
  "$(awk -F'\t' '$5=="Home" {print $4}' <<<"$list")" "yes"
assert_equals "an unknown network is not saved" \
  "$(awk -F'\t' '$5=="Open Net" {print $4}' <<<"$list")" "no"
assert_equals "an empty security field reads as open" \
  "$(awk -F'\t' '$5=="Open Net" {print $2}' <<<"$list")" "open"
assert_equals "one row per name, strongest first" \
  "$(grep -c . <<<"$list")" "3"
assert_equals "keeps the strongest of a repeated name" \
  "$(awk -F'\t' '$5=="Cafe" {print $1}' <<<"$list")" "90"

: >"$NM_CALLS"
"$LIST" >/dev/null
assert_equals "the default list does not scan the radio" \
  "$(grep -c -- '--rescan no' "$NM_CALLS")" "1"

: >"$NM_CALLS"
"$LIST" --rescan >/dev/null
assert_equals "--rescan asks for a fresh sweep" \
  "$(grep -c -- '--rescan yes' "$NM_CALLS")" "1"

# An SSID with a colon must survive the field split, which is why the name is
# queried last and rejoined.
export NM_SCAN=$':60:WPA2:Guest:5G\n'
assert_equals "matches an SSID containing a colon" \
  "$("$LIST" | cut -f5)" "Guest:5G"

# ── The actions ──────────────────────────────────────────────────────────────

export NM_SAVED=$'Cafe\n'
: >"$NM_CALLS"
"$JOIN" "Cafe" "hunter2"
assert_equals "a join passes the passphrase through" \
  "$(grep -c 'device wifi connect Cafe password hunter2' "$NM_CALLS")" "1"

: >"$NM_CALLS"
"$JOIN" "Cafe"
assert_equals "a join without one leaves the saved secret alone" \
  "$(grep -c 'device wifi connect Cafe$' "$NM_CALLS")" "1"

NM_JOIN_STATUS=1 "$JOIN" "Cafe" 2>"$TMP/err" && fail "a failed join exits non-zero"
pass "a failed join exits non-zero"

if "$FORGET" "Unknown" 2>"$TMP/err"; then
  fail "forgetting an unsaved network is refused"
fi
assert_equals "forgetting an unsaved network says so" \
  "$(<"$TMP/err")" "Error: no saved profile named Unknown."

: >"$NM_CALLS"
"$FORGET" "Cafe"
assert_equals "forget deletes the profile by name" \
  "$(grep -c 'connection delete id Cafe' "$NM_CALLS")" "1"

# ── The radio ────────────────────────────────────────────────────────────────

assert_equals "radio status reports enabled as JSON" \
  "$(NM_RADIO=enabled "$RADIO" status)" \
  '{"enabled":true,"tooltip":"Wi-Fi on - click to turn the radio off"}'
assert_equals "radio status reports disabled" \
  "$(NM_RADIO=disabled "$RADIO" status | cut -d, -f1)" '{"enabled":false'

: >"$NM_CALLS"
NM_RADIO=enabled "$RADIO" toggle
assert_equals "toggle turns an enabled radio off" \
  "$(grep -c 'radio wifi off' "$NM_CALLS")" "1"

: >"$NM_CALLS"
NM_RADIO=disabled "$RADIO" toggle
assert_equals "toggle turns a disabled radio on" \
  "$(grep -c 'radio wifi on' "$NM_CALLS")" "1"

echo
echo "All network tests passed."
