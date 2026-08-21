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
CHOOSER="$ROOT/bin/monarch-setup-dns"
PANEL="$ROOT/default/noctalia/plugins/monarch-network/panel.luau"

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
  *"DEVICE,TYPE device status"*) printf '%s\n' "${NM_DEVICES-wlan0:wifi}" ;;
  *"DEVICE,TYPE,STATE device status"*) printf 'wlan0:wifi:connected\n' ;;
  *"-g NAME connection show"*) printf '%s' "$NM_SAVED" ;;
  *"radio wifi off"*|*"radio wifi on"*) : ;;
  *"radio wifi"*) printf '%s\n' "${NM_RADIO:-enabled}" ;;
  *"device wifi connect"*) exit "${NM_JOIN_STATUS:-0}" ;;
  *"connection add type wifi"*) exit "${NM_ADD_STATUS:-0}" ;;
  *"connection edit uuid"*) cat >>"$NM_EDIT_INPUT"; exit "${NM_EDIT_STATUS:-0}" ;;
  *"connection up uuid"*) exit "${NM_UP_STATUS:-0}" ;;
  *"connection delete"*) exit "${NM_DELETE_STATUS:-0}" ;;
esac
STUB

cat >"$TMP/bin/iw" <<'STUB'
#!/bin/bash
printf 'Connected to 00:11 (on wlan0)\n\tSSID: %s\n\tfreq: %s\n\tsignal: -42 dBm\n\ttx bitrate: 130.0 MBit/s\n' \
  "$IW_SSID" "$IW_FREQ"
STUB

printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/ping"
cat >"$TMP/bin/uuidgen" <<'STUB'
#!/bin/bash
echo fixed-uuid
STUB

# NOCTALIA_UP decides whether the shell answers, which is what picks the branch.
cat >"$TMP/bin/noctalia" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOCTALIA_CALLS"
[[ ${NOCTALIA_UP:-yes} == yes ]] || exit 1
STUB
chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export NM_CALLS="$TMP/calls" NOCTALIA_CALLS="$TMP/ipc" NM_EDIT_INPUT="$TMP/edit"
: >"$NM_CALLS"
: >"$NOCTALIA_CALLS"
: >"$NM_EDIT_INPUT"

# monarch-network-status tells wireless from wired, and reads its byte counters,
# out of /sys/class/net. MONARCH_SYS_NET moves that root onto the tree above, so
# both branches and both counters are exercised without a card.
export MONARCH_SYS_NET="$TMP/sys"
printf '11\n' >"$TMP/sys/eth0/speed"
printf 'full\n' >"$TMP/sys/eth0/duplex"
mkdir -p "$TMP/sys/eth0/statistics" "$TMP/sys/wlan0/statistics"
printf '4096\n' >"$TMP/sys/eth0/statistics/rx_bytes"
printf '2048\n' >"$TMP/sys/eth0/statistics/tx_bytes"

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
assert_equals "reports the gateway" \
  "$(awk '$1=="gateway" {print $2}' <<<"$verbose")" "192.168.1.1"
assert_equals "reports the received byte counter" \
  "$(awk '$1=="rx_bytes" {print $2}' <<<"$verbose")" "4096"
assert_equals "reports the sent byte counter" \
  "$(awk '$1=="tx_bytes" {print $2}' <<<"$verbose")" "2048"
assert_equals "a device with no wireless directory reads as ethernet" \
  "$(awk '$1=="type" {print $2}' <<<"$verbose")" "ethernet"
assert_equals "reports the negotiated ethernet speed" \
  "$(awk '$1=="speed" {print $2}' <<<"$verbose")" "11"

wireless=$(IP_ROUTE_JSON='[{"dev":"wlan0","gateway":"10.0.0.1","prefsrc":"10.0.0.5"}]' "$STATUS" --verbose)
assert_equals "a device with one takes the wireless branch" \
  "$(awk '$1=="type" {print $2}' <<<"$wireless")" "wifi"
assert_equals "the wireless branch reports the signal in dBm" \
  "$(awk '$1=="signal_dbm" {print $2}' <<<"$wireless")" "-42"

printf '[Resolve]\nDNSOverTLS=no\n' >"$MONARCH_RESOLVED_CONF"
assert_equals "a file with no DNS= is DHCP" \
  "$("$STATUS" --verbose | awk '$1=="dns" {print $2}')" "DHCP"

printf '[Resolve]\nDNS=192.168.1.1\n' >"$MONARCH_RESOLVED_CONF"
assert_equals "anything else is Custom" \
  "$("$STATUS" --verbose | awk '$1=="dns" {print $2}')" "Custom"

# The resolved.conf sniff above is the fallback. With the monarch-dns package
# installed the command owns the answer, because it also reads NetworkManager's
# global-dns override — which wins over resolved.conf, so sniffing alone would
# report the wrong provider. Asserted by reading the source rather than by
# planting a binary in /usr/bin, which a test has no business doing.
grep -q 'if \[\[ -x /usr/bin/monarch-dns \]\]' "$STATUS" ||
  fail "status defers to the packaged monarch-dns when it is installed"
pass "status defers to the packaged monarch-dns when it is installed"

# ── The DNS chooser ──────────────────────────────────────────────────────────

# Same reason as above: what these pin is which path gets elevated, and a test
# may not plant a binary in /usr/bin to find out. The rule naming that path
# lives with the package, in monarch-pkgs, and so does the test for its shape.

grep -Fxq 'PACKAGED_DNS=/usr/bin/monarch-dns' "$CHOOSER" ||
  fail "the chooser hands over to the path the grant names"
pass "the chooser hands over to the path the grant names"

# The guard that matters: writing DNS lived here too, and the two copies drifted.
if grep -qE 'resolved\.conf|systemd/network|nmcli connection modify' "$CHOOSER"; then
  fail "the chooser writes no DNS configuration of its own"
fi
pass "the chooser writes no DNS configuration of its own"

grep -q 'monarch-pkg-add monarch-dns' "$CHOOSER" ||
  fail "the chooser installs the package the panel sends it here for"
pass "the chooser installs the package the panel sends it here for"

grep -Fq 'local PACKAGED_DNS = "/usr/bin/monarch-dns"' "$PANEL" ||
  fail "the panel elevates the same path and no other"
pass "the panel elevates the same path and no other"

# Custom takes servers from the caller, which is why the grant leaves it out: a
# panel routing it there would hand user input to a line that never stops to ask.
grep -q 'provider ~= "Custom"' "$PANEL" ||
  fail "the panel keeps Custom off the passwordless path"
pass "the panel keeps Custom off the passwordless path"

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

# A dual-band router under one name is two BSSes, and the star sits on the one
# the radio associated with — which is not always the strongest.
export NM_SCAN=$':90:WPA2:Cafe\n*:40:WPA2:Cafe\n'
assert_equals "the in-use star is found on any BSS of the name" \
  "$("$LIST" | cut -f3)" "yes"

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

# ── Enterprise (802.1X) ──────────────────────────────────────────────────────

JOIN_EAP="$ROOT/bin/monarch-wifi-enterprise"

if "$JOIN_EAP" "eduroam" 2>"$TMP/err"; then
  fail "an enterprise join without an identity is refused"
fi
pass "an enterprise join without an identity is refused"

: >"$NM_CALLS"
: >"$NM_EDIT_INPUT"
"$JOIN_EAP" "eduroam" "you@univ.fr" "hunter2"
assert_equals "the profile is keyed wpa-eap" \
  "$(grep -c 'wifi-sec.key-mgmt wpa-eap' "$NM_CALLS")" "1"
assert_equals "it asks for PEAP under the identity given" \
  "$(grep -c '802-1x.eap peap .*802-1x.identity you@univ.fr' "$NM_CALLS")" "1"
assert_equals "it is brought up by uuid, not by name" \
  "$(grep -c 'connection up uuid fixed-uuid' "$NM_CALLS")" "1"

# The whole reason for `connection edit`: nmcli takes no secret on `add`, and an
# argument would leave the passphrase in a world-readable /proc/<pid>/cmdline.
assert_equals "the passphrase reaches nmcli on stdin" \
  "$(awk '/^set 802-1x.password/ { print $3 }' "$NM_EDIT_INPUT")" "hunter2"
assert_equals "and never through its argv" \
  "$(grep -c hunter2 "$NM_CALLS" || true)" "0"

# A profile that never came up shadows the SSID in the saved list, so the next
# attempt would reuse the identity that just failed instead of asking again.
: >"$NM_CALLS"
NM_UP_STATUS=1 "$JOIN_EAP" "eduroam" "you@univ.fr" "hunter2" 2>"$TMP/err" &&
  fail "a failed enterprise join exits non-zero"
pass "a failed enterprise join exits non-zero"
assert_equals "a failed enterprise join discards its profile" \
  "$(grep -c 'connection delete uuid fixed-uuid' "$NM_CALLS")" "1"

# ── The radio ────────────────────────────────────────────────────────────────

assert_equals "radio status reports enabled as JSON" \
  "$(NM_RADIO=enabled "$RADIO" status)" \
  '{"enabled":true,"present":true,"tooltip":"Wi-Fi on - click to turn the radio off"}'
assert_equals "radio status reports disabled" \
  "$(NM_RADIO=disabled "$RADIO" status | cut -d, -f1)" '{"enabled":false'

# A machine with no adapter must not read as a radio someone switched off.
assert_equals "radio status reports a missing adapter" \
  "$(NM_DEVICES= NM_RADIO=enabled "$RADIO" status)" \
  '{"enabled":false,"present":false,"tooltip":"No Wi-Fi adapter"}'

# The read never goes through the shell: NetworkManager owns the state, asking
# it directly cannot go stale, and `status` must answer with no shell running.
: >"$NOCTALIA_CALLS"
NM_RADIO=enabled "$RADIO" status >/dev/null
assert_equals "status asks NetworkManager, not the shell" \
  "$(grep -c wifi "$NOCTALIA_CALLS" || true)" "0"

# Writes prefer the IPC, so Noctalia's own panel is not left behind.
for action in "toggle:wifi-toggle" "on:wifi-enable" "off:wifi-disable"; do
  : >"$NM_CALLS"; : >"$NOCTALIA_CALLS"
  NOCTALIA_UP=yes NM_RADIO=enabled "$RADIO" "${action%%:*}"
  assert_equals "${action%%:*} goes through the shell when it is up" \
    "$(grep -c "msg ${action##*:}" "$NOCTALIA_CALLS")" "1"
  assert_equals "${action%%:*} leaves nmcli alone when the shell answered" \
    "$(grep -c 'radio wifi' "$NM_CALLS" || true)" "0"
done

# And fall back when it is not, which is what keeps the command usable from a
# TTY, over SSH, or during an install.
: >"$NM_CALLS"
NOCTALIA_UP=no NM_RADIO=enabled "$RADIO" toggle
assert_equals "toggle falls back and turns an enabled radio off" \
  "$(grep -c 'radio wifi off' "$NM_CALLS")" "1"

: >"$NM_CALLS"
NOCTALIA_UP=no NM_RADIO=disabled "$RADIO" toggle
assert_equals "toggle falls back and turns a disabled radio on" \
  "$(grep -c 'radio wifi on' "$NM_CALLS")" "1"

: >"$NM_CALLS"
NOCTALIA_UP=no "$RADIO" on
assert_equals "on falls back to nmcli" \
  "$(grep -c 'radio wifi on' "$NM_CALLS")" "1"

echo
echo "All network tests passed."
