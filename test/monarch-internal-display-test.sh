#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

export PATH="$TMP/bin:$ROOT/bin:/usr/bin"
export NIRI_CALLS="$TMP/niri-calls" MIRROR_CALLS="$TMP/mirror-calls"
export OUTPUTS_JSON="$TMP/outputs.json" FOCUSED=LVDS-1

for connector in eDP-1 LVDS-1 DSI-1; do
  monarch-hw-display-internal "$connector" || fail "$connector must be internal"
done
pass "common laptop panel connectors are internal"

for connector in DP-1 HDMI-A-1 VGA-1 VIRTUAL-1; do
  monarch-hw-display-internal "$connector" && fail "$connector must be external"
done
pass "external connector types remain external"

set +e
monarch-hw-display-internal eDP-1 extra
status=$?
set -e
((status == 2)) || fail "the connector predicate must require one argument"
pass "the connector predicate rejects an invalid invocation"

drm_path="$TMP/drm"
write_connectors() {
  rm -rf "$drm_path"
  mkdir -p "$drm_path"

  local connector state
  while (($#)); do
    connector=$1
    state=$2
    mkdir -p "$drm_path/card0-$connector"
    printf '%s\n' "$state" >"$drm_path/card0-$connector/status"
    shift 2
  done
}

has_external_monitor() {
  MONARCH_DRM_PATH="$drm_path" monarch-hw-external-monitors
}

write_connectors
if output=$(has_external_monitor 2>&1); then
  fail "an empty DRM tree must not report an external monitor"
fi
[[ -z $output ]] || fail "an empty DRM tree must be quiet"
pass "an empty DRM tree has no external monitor"

for connector in eDP-1 LVDS-1 DSI-1; do
  write_connectors "$connector" connected
  has_external_monitor && fail "$connector must not count as external"
done
pass "connected internal panels do not satisfy the external-monitor guard"

write_connectors LVDS-1 connected DP-1 connected
has_external_monitor || fail "DP-1 must be found alongside LVDS-1"
pass "an external monitor is found alongside an LVDS panel"

write_connectors DSI-1 connected HDMI-A-1 disconnected
has_external_monitor && fail "a disconnected HDMI output must not count"
pass "disconnected external outputs are ignored"

cat >"$TMP/bin/niri" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NIRI_CALLS"
if [[ $* == "msg --json outputs" ]]; then
  cat "$OUTPUTS_JSON"
elif [[ $* == "msg --json focused-output" ]]; then
  printf '{"name":"%s"}\n' "$FOCUSED"
fi
STUB

cat >"$TMP/bin/notify-send" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$TMP/bin/setsid" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$MIRROR_CALLS"
STUB

cat >"$TMP/bin/wl-mirror" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$TMP"/bin/*

write_outputs() {
  printf '{"%s":{"current_mode":0},"%s":{"current_mode":0}}\n' \
    "$1" "$2" >"$OUTPUTS_JSON"
}

write_outputs LVDS-1 HDMI-A-1
: >"$NIRI_CALLS"
"$ROOT/bin/monarch-niri-monitor-internal" on
grep -Fxq 'msg output LVDS-1 on' "$NIRI_CALLS" ||
  fail "the laptop-display toggle must select LVDS-1"
pass "the laptop-display toggle selects an LVDS panel"

write_outputs DSI-1 HDMI-A-1
: >"$MIRROR_CALLS"
"$ROOT/bin/monarch-niri-monitor-internal-mirror" on all
for _ in {1..20}; do
  [[ -s $MIRROR_CALLS ]] && break
  sleep 0.01
done
grep -Fxq 'uwsm-app -- wl-mirror --fullscreen-output HDMI-A-1 DSI-1' "$MIRROR_CALLS" ||
  fail "mirroring must use DSI-1 only as the source"
pass "mirroring separates a DSI panel from its external target"

: >"$MIRROR_CALLS"
FOCUSED=DSI-1 "$ROOT/bin/monarch-niri-monitor-internal-mirror" on single
for _ in {1..20}; do
  [[ -s $MIRROR_CALLS ]] && break
  sleep 0.01
done
grep -Fxq 'uwsm-app -- wl-mirror --fullscreen-output HDMI-A-1 DSI-1' "$MIRROR_CALLS" ||
  fail "an internal focused output must not become its own mirror target"
pass "single-display mirroring skips a focused internal panel"

source "$ROOT/bin/monarch-hw-recover-internal-monitor"
[[ $(internal_output) == DSI-1 ]] || fail "the recovery watcher must select DSI-1"
pass "the recovery watcher uses the shared internal-display classification"
