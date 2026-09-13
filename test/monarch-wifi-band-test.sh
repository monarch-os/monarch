#!/bin/bash

# Exercises band detection, the availability guard and the revert-on-failure
# path against a fake nmcli and iw, so none of it needs a radio.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BAND="$ROOT/bin/monarch-wifi-band"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

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

# The fake records every call so the test can assert on what was asked of
# NetworkManager, and reads its answers from the environment.
cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NM_CALLS"
case "$*" in
  *"DEVICE,TYPE,STATE device status"*) printf 'wlan0:wifi:connected\n' ;;
  *"GENERAL.CONNECTION device show"*)  printf '%s\n' "$NM_PROFILE" ;;
  *"802-11-wireless.band connection show"*) printf '%s\n' "${NM_BAND:-}" ;;
  *"FREQ,SSID dev wifi list"*) printf '%s' "$NM_SCAN" ;;
  *"connection up"*) exit "${NM_UP_STATUS:-0}" ;;
esac
STUB

# No default route in the sandbox, so monarch-wifi-device falls through to nmcli.
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/ip"

cat >"$TMP/bin/iw" <<'STUB'
#!/bin/bash
printf 'Connected to 00:11:22:33:44:55 (on wlan0)\n\tSSID: %s\n\tfreq: %s\n' "$IW_SSID" "$IW_FREQ"
STUB
chmod +x "$TMP"/bin/*

export PATH="$TMP/bin:$ROOT/bin:$PATH"
export NM_CALLS="$TMP/calls" NM_PROFILE="Cafe" IW_SSID="Cafe" IW_FREQ="5745"
export NM_SCAN=$'2412 MHz:Cafe\n5745 MHz:Cafe\n2437 MHz:Neighbour\n'
: >"$NM_CALLS"

status=$("$BAND")
# The panel names the network the pin applies to, so the SSID is part of status.
assert_equals "names the connected network"  "$(awk '$1=="ssid"      {print $2}' <<<"$status")" "Cafe"
assert_equals "reports the band in use"      "$(awk '$1=="band"      {print $2}' <<<"$status")" "5"
assert_equals "lists both bands of the SSID" "$(awk '$1=="available" {$1=""; sub(/^ /,""); print}' <<<"$status")" "2.4 5"
assert_equals "reports no pin as auto"       "$(awk '$1=="selected"  {print $2}' <<<"$status")" "auto"

# A 6GHz-only scan hit must not make 6 selectable when the AP answers on 5.
: >"$NM_CALLS"
if err=$("$BAND" 6 2>&1 >/dev/null); then
  fail "refuses a band the network does not answer on"
fi
assert_equals "explains the refusal" "$err" "Error: 6GHz is not available on this network."
assert_equals "asks NetworkManager for no change" "$(grep -c 'connection modify' "$NM_CALLS" || true)" "0"

: >"$NM_CALLS"
"$BAND" 2.4
assert_equals "pins 2.4GHz as nmcli's bg" \
  "$(grep -m1 'connection modify' "$NM_CALLS")" "connection modify Cafe 802-11-wireless.band bg"
assert_equals "reassociates so the pin takes effect" \
  "$(grep -c 'connection up Cafe' "$NM_CALLS" || true)" "1"

: >"$NM_CALLS"
NM_BAND="a" "$BAND" auto
assert_equals "auto clears the pin" \
  "$(grep -m1 'connection modify' "$NM_CALLS")" "connection modify Cafe 802-11-wireless.band "

# Nothing to do, so nothing is touched: a no-op must not bounce the connection.
: >"$NM_CALLS"
NM_BAND="bg" "$BAND" 2.4
assert_equals "an unchanged band is left alone" \
  "$(grep -cE 'connection (modify|up)' "$NM_CALLS" || true)" "0"

# The radio cannot come up on the requested band.
: >"$NM_CALLS"
if err=$(NM_BAND="a" NM_UP_STATUS=1 "$BAND" 2.4 2>&1 >/dev/null); then
  fail "fails when the radio cannot reassociate"
fi
assert_equals "says it reverted" "$err" "Error: could not connect on 2.4; reverted to previous band."
assert_equals "puts the previous band back" \
  "$(grep 'connection modify' "$NM_CALLS" | tail -1)" "connection modify Cafe 802-11-wireless.band a"

# An SSID with a colon survives nmcli's field splitting.
: >"$NM_CALLS"
NM_SCAN=$'2412 MHz:Cafe:Guest\n5745 MHz:Cafe:Guest\n' IW_SSID="Cafe:Guest" NM_PROFILE="Cafe:Guest" \
  status=$("$BAND")
assert_equals "matches an SSID containing a colon" \
  "$(awk '$1=="available" {$1=""; sub(/^ /,""); print}' <<<"$status")" "2.4 5"

printf '\nAll Wi-Fi band tests passed.\n'
