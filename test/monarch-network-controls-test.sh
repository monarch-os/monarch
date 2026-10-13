#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
mkdir -p "$TMP/sys/eth0/device" "$TMP/sys/wlan0/device" "$TMP/sys/lan0"
export MONARCH_SYS_NET="$TMP/sys"
export CALLS="$TMP/calls"
export PATH="$TMP/bin:$PATH"

cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CALLS"
if [[ -n ${FAIL_ON_CALL:-} && $* == "$FAIL_ON_CALL" && ! -e $METRIC_STATE/failed ]]; then
  touch "$METRIC_STATE/failed"
  exit 1
fi
if [[ ${FAIL_RESTORE:-false} == "true" && $* == "connection modify uuid wifi-uuid ipv4.route-metric -1 ipv6.route-metric -1" && -e $METRIC_STATE/failed ]]; then
  exit 1
fi
case "$*" in
  *"DEVICE,TYPE,STATE device status")
    printf 'eth0:ethernet:%s\nwlan0:wifi:connected\neth1:ethernet:disconnected\neth2:ethernet:unmanaged\ntun0:tun:connected\nlan0:ethernet:connected\n' "${WIRED_STATE:-connected}" ;;
  *"GENERAL.CON-UUID device show eth0") echo wired-uuid ;;
  *"GENERAL.CON-UUID device show wlan0") echo wifi-uuid ;;
  *"GENERAL.CON-UUID device show lan0") echo local-uuid ;;
  *"GENERAL.CON-UUID device show"*) echo -- ;;
  *"ipv4.route-metric,ipv6.route-metric connection show uuid wired-uuid") printf '%s\n%s\n' "${WIRED_METRIC:--1}" "${WIRED_METRIC6:-${WIRED_METRIC:--1}}" ;;
  *"ipv4.route-metric,ipv6.route-metric connection show uuid"*) printf '%s\n' -1 -1 ;;
  *"connection modify"*)
    if [[ -n ${METRIC_STATE:-} ]]; then printf '%s\n%s\n' "$6" "$8" >"$METRIC_STATE/$4"; fi
    exit "${MODIFY_STATUS:-0}" ;;
  *"device reapply"*) exit "${REAPPLY_STATUS:-0}" ;;
  *"device connect"*|*"device disconnect"*) exit "${DEVICE_STATUS:-0}" ;;
  *) exit 2 ;;
esac
STUB

cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
case "$*" in
  *"-4 route show default")
    fallback='[{"dev":"eth0","metric":100},{"dev":"wlan0","metric":600}]'
    printf '%s\n' "${ROUTES4:-$fallback}" ;;
  *"-6 route show default") printf '%s\n' "${ROUTES6:-[]}" ;;
  *"-j address show")
    fallback='[{"ifname":"eth0","addr_info":[{"family":"inet","local":"192.168.1.20","prefixlen":24,"scope":"global"},{"family":"inet","local":"192.168.1.21","prefixlen":24,"scope":"global"},{"family":"inet6","local":"2001:db8::20","prefixlen":64,"scope":"global"},{"family":"inet6","local":"fe80::20","prefixlen":64,"scope":"link"},{"family":"inet6","local":"2001:db8::99","prefixlen":64,"scope":"global","tentative":true}]},{"ifname":"wlan0","addr_info":[{"family":"inet","local":"10.0.0.5","prefixlen":24,"scope":"global"}]}]'
    printf '%s\n' "${ADDRESSES:-$fallback}" ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/"*

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_call() { grep -Fxq -- "$1" "$CALLS" || fail "missing call: $1"; }
reject() {
  : >"$CALLS"
  if "$@" >"$TMP/out" 2>"$TMP/err"; then fail "accepted invalid action: $*"; fi
  if grep -Eq 'connection modify|device (connect|disconnect|reapply)' "$CALLS"; then
    fail "invalid action changed network state"
  fi
}

interfaces=$("$ROOT/bin/monarch-network-interfaces")
jq -e 'length == 5 and any(.[]; .iface == "eth1" and .connected == false and .uuid == "")
  and any(.[]; .iface == "eth2" and .managed == false)
   and any(.[]; .iface == "lan0" and .routable == false and .virtual)
   and any(.[]; .iface == "eth0" and .virtual == false and .metrics == [-1, -1])' <<<"$interfaces" >/dev/null || fail "interface state"
pass "lists disconnected and unmanaged Ethernet, excludes tunnels and distinguishes local-only links"

ROUTES4='[]' ROUTES6='[{"dev":"wlan0"}]' "$ROOT/bin/monarch-network-interfaces" |
  jq -e 'any(.[]; .iface == "wlan0" and .routable)' >/dev/null || fail "IPv6 default route"
pass "IPv6-only Internet connections are eligible"

WIRED_METRIC=50 "$ROOT/bin/monarch-network-interfaces" |
  jq -e 'any(.[]; .iface == "eth0" and .metrics == [50, 50])' >/dev/null || fail "saved priority"
pass "reports saved priority independently of the route currently in use"

jq -e 'any(.[]; .iface == "eth0" and (.addresses | length) == 4
    and any(.addresses[]; .address == "192.168.1.21" and .prefix == 24)
    and any(.addresses[]; .address == "fe80::20" and .scope == "link"))
  and any(.[]; .iface == "wlan0" and .addresses[0].address == "10.0.0.5")
  and any(.[]; .iface == "eth1" and .addresses == [])' <<<"$interfaces" >/dev/null || fail "per-interface addresses"
pass "keeps multiple IPv4 and IPv6 addresses on their owning interface and excludes tentative addresses"

ROUTES4='[{"dev":"eth0","gateway":"192.168.1.1"}]' \
  ROUTES6='[{"dev":"eth0","gateway":"fe80::1"},{"dev":"eth0","gateway":"fe80::1"}]' \
  "$ROOT/bin/monarch-network-interfaces" >"$TMP/gateways"
jq -e 'any(.[]; .iface == "eth0" and (.gateways | length) == 2
    and any(.gateways[]; .family == "inet" and .address == "192.168.1.1")
    and any(.gateways[]; .family == "inet6" and .address == "fe80::1"))
  and any(.[]; .iface == "wlan0" and .routable == false and .gateways == []
    and .addresses[0].address == "10.0.0.5")' "$TMP/gateways" >/dev/null || fail "per-interface gateways"
pass "reports dual-stack gateways without duplicates and still shows local-only connection addresses"

ADDRESSES='[]' "$ROOT/bin/monarch-network-interfaces" |
  jq -e 'all(.[]; .addresses == [])' >/dev/null || fail "missing addresses"
pass "an interface with no address has an empty address list"

for action in on off; do
  : >"$CALLS"
  "$ROOT/bin/monarch-network-ethernet" eth1 "$action"
  if [[ $action == "on" ]]; then assert_call "device connect eth1"; else assert_call "device disconnect eth1"; fi
done
pass "Ethernet activation and deactivation address the selected device"
reject "$ROOT/bin/monarch-network-ethernet" wlan0 off
reject "$ROOT/bin/monarch-network-ethernet" eth2 on
reject "$ROOT/bin/monarch-network-ethernet" lan0 on
reject "$ROOT/bin/monarch-network-ethernet" lan0 off
reject "$ROOT/bin/monarch-network-ethernet" missing off
reject "$ROOT/bin/monarch-network-ethernet" eth0 invalid
reject "$ROOT/bin/monarch-network-ethernet" eth0 on extra
pass "refuses Wi-Fi, unmanaged and nonexistent devices and invalid arguments"

: >"$CALLS"
"$ROOT/bin/monarch-network-route" wlan0
assert_call "connection modify uuid wifi-uuid ipv4.route-metric 50 ipv6.route-metric 50"
assert_call "connection modify uuid wired-uuid ipv4.route-metric 600 ipv6.route-metric 600"
assert_call "device reapply eth0"
assert_call "device reapply wlan0"
if grep -Eq 'connection modify uuid local-uuid|device reapply lan0|tun0|connection (up|down)|never-default' "$CALLS"; then fail "modified unrelated routing"; fi
pass "saves dual-stack priority with fallback, reapplies links and leaves VPN and local-only profiles alone"

: >"$CALLS"
"$ROOT/bin/monarch-network-route" auto
assert_call "connection modify uuid wifi-uuid ipv4.route-metric -1 ipv6.route-metric -1"
assert_call "connection modify uuid wired-uuid ipv4.route-metric -1 ipv6.route-metric -1"
pass "automatic routing restores NetworkManager metrics"

reject "$ROOT/bin/monarch-network-route" eth1
reject "$ROOT/bin/monarch-network-route" eth2
reject "$ROOT/bin/monarch-network-route" lan0
reject "$ROOT/bin/monarch-network-route" tun0
reject "$ROOT/bin/monarch-network-route" missing
reject "$ROOT/bin/monarch-network-route" wlan0 extra
pass "priority requires a connected physical interface with a default route"

if MODIFY_STATUS=1 "$ROOT/bin/monarch-network-route" wlan0 >/dev/null 2>&1; then fail "ignored modify failure"; fi
if REAPPLY_STATUS=1 "$ROOT/bin/monarch-network-route" wlan0 >/dev/null 2>&1; then fail "ignored reapply failure"; fi
if DEVICE_STATUS=1 "$ROOT/bin/monarch-network-ethernet" eth0 off >/dev/null 2>&1; then fail "ignored device failure"; fi
pass "NetworkManager failures propagate to the panel"

PANEL="$ROOT/default/noctalia/plugins/monarch-network/panel.luau"
grep -Fq 'onClick = "onRescanClicked"' "$PANEL" || fail "missing manual rescan"
grep -Fq 'if scanning then return end' "$PANEL" || fail "overlapping scans"
grep -Fq 'radioPresent and radioOn and busy == ""' "$PANEL" || fail "scan on disabled radio"
pass "panel exposes manual rescan and guards overlapping and disabled-radio scans"
grep -Fq 'device.managed and not device.virtual' "$PANEL" || fail "virtual device clutter"
grep -Fq 'onClick = "onDetailsClicked"' "$PANEL" || fail "missing details disclosure"
grep -Fq 'detailsOpen = context == "details"' "$PANEL" || fail "missing direct details view"
grep -Fq 'variant = preferred and "primary" or "outline"' "$PANEL" || fail "priority confused with active route"
pass "panel hides virtual devices, collapses details and distinguishes preference from active route"
grep -Fq 'for _, node in ipairs(interfaceDetails())' "$PANEL" || fail "missing per-interface detail cards"
grep -Fq 'local active = device.iface == info.iface' "$PANEL" || fail "missing active output marker"
pass "details render every connected physical interface separately and identify the active Internet output"

: >"$CALLS"
ROUTES4='[{"dev":"eth0"},{"dev":"wlan0"},{"dev":"lan0"}]' "$ROOT/bin/monarch-network-route" wlan0
if grep -Eq 'connection modify uuid local-uuid|device reapply lan0' "$CALLS"; then
  fail "preferring a physical link rewrites a hidden virtual profile"
fi
ROUTES4='[{"dev":"eth0"},{"dev":"wlan0"},{"dev":"lan0"}]' reject "$ROOT/bin/monarch-network-route" lan0
: >"$CALLS"
ROUTES4='[{"dev":"eth0"},{"dev":"wlan0"},{"dev":"lan0"}]' "$ROOT/bin/monarch-network-route" auto
if grep -Eq 'connection modify uuid local-uuid|device reapply lan0' "$CALLS"; then
  fail "automatic metrics rewrite a hidden virtual profile"
fi
pass "priority and Auto exclude virtual profiles even when they have default routes"

WIRED_STATE='connected (externally)' "$ROOT/bin/monarch-network-interfaces" |
  jq -e 'any(.[]; .iface == "eth0" and .connected and .managed == false and .metrics == [])' >/dev/null || fail "external connection state"
for action in on off; do
  WIRED_STATE='connected (externally)' reject "$ROOT/bin/monarch-network-ethernet" eth0 "$action"
done
WIRED_STATE='connected (externally)' reject "$ROOT/bin/monarch-network-route" eth0
for target in wlan0 auto; do
  : >"$CALLS"
  WIRED_STATE='connected (externally)' "$ROOT/bin/monarch-network-route" "$target"
  if grep -Eq 'connection modify uuid wired-uuid|device reapply eth0' "$CALLS"; then
    fail "priority rewrites an externally configured connection"
  fi
done
pass "external connections stay connected but are excluded from activation and route changes"

for state in 'connecting' 'connecting (getting IP configuration)' 'connecting (prepare)'; do
  WIRED_STATE=$state "$ROOT/bin/monarch-network-interfaces" |
    jq -e 'any(.[]; .iface == "eth0" and .connecting and .connected == false)' >/dev/null || fail "connecting state"
  WIRED_STATE=$state reject "$ROOT/bin/monarch-network-ethernet" eth0 on
done
pass "connecting states are normalized and reject duplicate Ethernet activation"

export METRIC_STATE="$TMP/metrics"
mkdir -p "$METRIC_STATE"
for target in wlan0 auto; do
  metric=50
  [[ $target != "auto" ]] || metric=-1
  for failure in 'device reapply eth0' \
    "connection modify uuid wifi-uuid ipv4.route-metric $metric ipv6.route-metric $metric" \
    'device reapply wlan0'; do
    rm -f "$METRIC_STATE/failed"
    printf '123\n456\n' >"$METRIC_STATE/wired-uuid"
    printf '%s\n' -1 -1 >"$METRIC_STATE/wifi-uuid"
    : >"$CALLS"
    if WIRED_METRIC=123 WIRED_METRIC6=456 FAIL_ON_CALL=$failure "$ROOT/bin/monarch-network-route" "$target" >"$TMP/out" 2>"$TMP/err"; then
      fail "accepted failed route update: $failure"
    fi
    [[ $(cat "$METRIC_STATE/wired-uuid") == $'123\n456' ]] || fail "did not restore original dual-stack metrics: $failure"
    [[ $(cat "$METRIC_STATE/wifi-uuid") == $'-1\n-1' ]] || fail "did not restore selected profile: $failure"
    assert_call "device reapply eth0"
  done
done
pass "failed priority and Auto updates restore every attempted profile's original dual-stack metrics"

WIRED_METRIC=unknown reject "$ROOT/bin/monarch-network-route" wlan0
pass "missing original metrics prevent any route mutation"

rm -f "$METRIC_STATE/failed"
: >"$CALLS"
if WIRED_METRIC=123 WIRED_METRIC6=456 FAIL_ON_CALL='device reapply wlan0' FAIL_RESTORE=true \
  "$ROOT/bin/monarch-network-route" wlan0 >"$TMP/out" 2>"$TMP/err"; then fail "ignored rollback failure"; fi
grep -Fq 'could not restore saved metrics for wlan0' "$TMP/err" || fail "silent rollback failure"
assert_call "connection modify uuid wired-uuid ipv4.route-metric 123 ipv6.route-metric 456"
[[ $(cat "$METRIC_STATE/wired-uuid") == $'123\n456' ]] || fail "rollback stopped after one restoration failure"
pass "rollback failures are reported without skipping restoration of earlier profiles"
