#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

cat >"$TMP/bin/setsid" <<'EOF'
#!/bin/bash
[[ ${1:-} == "--fork" ]] && shift
exec "$@"
EOF

cat >"$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$NOTIFY_LOG"
if [[ " $* " == *" --action="* ]]; then
  printf '%s\n' "${NOTIFY_ACTION:-default}"
fi
EOF

cat >"$TMP/bin/action-target" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$ACTION_LOG"
EOF

chmod +x "$TMP/bin"/*

export NOTIFY_LOG="$TMP/notify.log"
export ACTION_LOG="$TMP/action.log"
PATH="$TMP/bin:/usr/bin"

mapfile0() {
  local file=$1
  mapfile -d '' -t ARGV <"$file"
}

PATH="$PATH" "$ROOT/bin/monarch-notification-send" -u critical -g G \
  --image "/tmp/preview with space.png" "Headline" "Body" -t 4000
mapfile0 "$NOTIFY_LOG"
[[ ${ARGV[0]} == "--app-name=Monarch" && ${ARGV[1]} == "-u" && ${ARGV[2]} == "critical" ]]
[[ ${ARGV[3]} == "-t" && ${ARGV[4]} == "4000" ]]
[[ ${ARGV[5]} == "--hint=string:image-path:/tmp/preview with space.png" ]]
[[ ${ARGV[6]} == "--" && ${ARGV[7]} == "G    Headline" && ${ARGV[8]} == "      Body" ]]

payload='$(touch should-not-exist); one argument'
PATH="$PATH" "$ROOT/bin/monarch-notification-send" -g X \
  "Action" "Keep argv" --action "Run" action-target "$payload" "two words"
mapfile0 "$ACTION_LOG"
[[ ${#ARGV[@]} == 2 ]]
[[ ${ARGV[0]} == "$payload" && ${ARGV[1]} == "two words" ]]
[[ ! -e should-not-exist ]]

if PATH="$PATH" "$ROOT/bin/monarch-notification-send" "Bad" \
  --action "Run" "action-target one" 2>/dev/null; then
  echo "Quoted action command was accepted" >&2
  exit 1
fi

if PATH="$PATH" "$ROOT/bin/monarch-notification-send" -u 2>/dev/null; then
  echo "Option without a value was accepted" >&2
  exit 1
fi

for invitation in \
  install/user/first-run/wifi.sh \
  install/user/first-run/setup-fingerprint.hook \
  install/user/first-run/setup-agent.hook \
  install/user/first-run/install-voxtype.hook; do
  grep -q -- '--action' "$ROOT/$invitation"
  ! grep -q -- '--exec' "$ROOT/$invitation"
done

for caller in \
  bin/monarch-capture-screenshot \
  bin/monarch-capture-screenrecording \
  bin/monarch-tailscale-receive; do
  grep -q 'monarch-notification-send' "$ROOT/$caller"
  grep -q -- '--action' "$ROOT/$caller"
done

screenrecording="$ROOT/bin/monarch-capture-screenrecording"
grep -Fq 'local preview="${filename%.mp4}-preview.png"' "$screenrecording"
grep -Fq 'ffmpeg -y -i "$filename"' "$screenrecording"
grep -Fq -- '--image "${preview:-$filename}"' "$screenrecording"
grep -A2 'sleep 2' "$screenrecording" | grep -Fq 'rm -f "$preview"'
grep -Fq -- '--fullscreen) FULLSCREEN="true"' "$screenrecording"

screenshot="$ROOT/bin/monarch-capture-screenshot"
[[ $(grep -Fc 'wl-copy --type image/png' "$screenshot") == 2 ]]
grep -Fq '^(-?[0-9]+),(-?[0-9]+)[[:space:]]' "$screenshot"

echo "Structured notification text and action argv checks pass"
