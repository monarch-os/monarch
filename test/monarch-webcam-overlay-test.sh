#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'status=$?; rm -rf "$TMP"; exit $status' EXIT

mkdir -p "$TMP/bin" "$TMP/runtime"
export MOCK_NIRI_STATE="$TMP/niri-state"
export MOCK_NIRI_LOG="$TMP/niri.log"

printf '100\n' >"$MOCK_NIRI_STATE.width"
printf '100\n' >"$MOCK_NIRI_STATE.height"
printf '0\n' >"$MOCK_NIRI_STATE.x"
printf '0\n' >"$MOCK_NIRI_STATE.y"

cat >"$TMP/bin/niri" <<'EOF'
#!/bin/bash

if [[ $* == "msg --json windows" ]]; then
  width=$(<"$MOCK_NIRI_STATE.width")
  height=$(<"$MOCK_NIRI_STATE.height")
  x=$(<"$MOCK_NIRI_STATE.x")
  y=$(<"$MOCK_NIRI_STATE.y")
  app_id=$(jq -r '.app_id' "$XDG_RUNTIME_DIR/monarch-screenrecord-webcam-$UID.json")
  jq -cn --arg app_id "$app_id" --argjson width "$width" --argjson height "$height" --argjson x "$x" --argjson y "$y" \
    '[{id: 42, pid: 123, app_id: $app_id, layout: {window_size: [$width, $height], tile_pos_in_workspace_view: [$x, $y]}}]'
elif [[ $* == "msg --json outputs" ]]; then
  jq -cn '{DP1: {name: "DP-1", logical: {x: 0, y: 0, width: 1920, height: 1080, scale: 1.0}}}'
elif [[ $* == "msg --json focused-output" ]]; then
  jq -cn '{name: "DP-1", logical: {x: 0, y: 0, width: 1920, height: 1080, scale: 1.0}}'
elif [[ $1 == "msg" && $2 == "action" ]]; then
  printf '%s\n' "${*:3}" >>"$MOCK_NIRI_LOG"
  case $3 in
  set-window-width) printf '%s\n' "${!#}" >"$MOCK_NIRI_STATE.width" ;;
  set-window-height) printf '%s\n' "${!#}" >"$MOCK_NIRI_STATE.height" ;;
  move-floating-window)
    while (($#)); do
      case $1 in
      --x) printf '%s\n' "$2" >"$MOCK_NIRI_STATE.x"; shift 2 ;;
      --y) printf '%s\n' "$2" >"$MOCK_NIRI_STATE.y"; shift 2 ;;
      *) shift ;;
      esac
    done
    ;;
  esac
fi
EOF
chmod +x "$TMP/bin/niri"

run_resize() {
  PATH="$TMP/bin:/usr/bin" XDG_RUNTIME_DIR="$TMP/runtime" \
    "$ROOT/bin/monarch-capture-webcam-resize" "$1"
}

jq -cn '{target: "monitor:DP-1", shape: "circle", app_id: "org.monarch.webcam-overlay.circle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize medium
grep -Fqx 'set-window-width --id 42 270' "$MOCK_NIRI_LOG"
grep -Fqx 'set-window-height --id 42 270' "$MOCK_NIRI_LOG"
grep -Fqx 'move-floating-window --id 42 --x 1610 --y 770' "$MOCK_NIRI_LOG"

: >"$MOCK_NIRI_LOG"
jq -cn '{target: "region:800x600+200+100", shape: "circle", app_id: "org.monarch.webcam-overlay.circle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize reset
grep -Fqx 'set-window-width --id 42 150' "$MOCK_NIRI_LOG"
grep -Fqx 'set-window-height --id 42 150' "$MOCK_NIRI_LOG"
grep -Fqx 'move-floating-window --id 42 --x 810 --y 510' "$MOCK_NIRI_LOG"

: >"$MOCK_NIRI_LOG"
jq -cn '{target: "region:800x600+200+100", shape: "rectangle", app_id: "org.monarch.webcam-overlay.rectangle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize large
grep -Fqx 'set-window-width --id 42 180' "$MOCK_NIRI_LOG"
grep -Fqx 'set-window-height --id 42 203' "$MOCK_NIRI_LOG"
grep -Fqx 'move-floating-window --id 42 --x 780 --y 457' "$MOCK_NIRI_LOG"

if run_resize huge >/dev/null 2>&1; then
  echo "Invalid webcam size was accepted" >&2
  exit 1
fi

for args in '--webcam-size=huge' '--webcam-shape=triangle'; do
  if MONARCH_SCREENRECORD_DIR="$TMP" HOME="$TMP" "$ROOT/bin/monarch-capture-screenrecording" "$args" >/dev/null 2>&1; then
    echo "Invalid screen recording webcam option was accepted: $args" >&2
    exit 1
  fi
done

grep -Fq 'match app-id="org.monarch.webcam-overlay.circle"' "$ROOT/default/niri/windows.kdl"
grep -Fq 'geometry-corner-radius 9999' "$ROOT/default/niri/windows.kdl"
grep -Fq 'clip-to-geometry true' "$ROOT/default/niri/windows.kdl"
grep -Fq 'open-focused false' "$ROOT/default/niri/windows.kdl"
grep -Fq 'opacity 1.0' "$ROOT/default/niri/windows.kdl"
grep -Fq -- '--wayland-app-id="$app_id"' "$ROOT/bin/monarch-capture-screenrecording"
grep -Fq 'monarch-capture-webcam-resize" "smaller"' "$ROOT/default/niri/binds.kdl"
grep -Fq 'monarch-capture-webcam-resize" "larger"' "$ROOT/default/niri/binds.kdl"

echo "Webcam overlay sizing, placement, identity and shape checks pass"
