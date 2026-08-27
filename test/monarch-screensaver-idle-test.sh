#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_screensaver_idle() {
  local config=$1

  grep -Eq '^behavior_order = \["screensaver", "lock", "screen-off"\]$' "$config"
  sed -n '/^[[:space:]]*\[idle\.behavior\.screensaver\]$/,/^$/p' "$config" |
    grep -Eq '^[[:space:]]*action = "command"$'
  sed -n '/^[[:space:]]*\[idle\.behavior\.screensaver\]$/,/^$/p' "$config" |
    grep -Eq '^[[:space:]]*command = "monarch-launch-screensaver"$'
  sed -n '/^[[:space:]]*\[idle\.behavior\.screensaver\]$/,/^$/p' "$config" |
    grep -Eq "^[[:space:]]*resume_command = \"pkill -f '\[o\]rg.monarch.screensaver'\"$"
}

assert_screensaver_idle "$ROOT/config/noctalia/config.toml"
! rg -n "pkill -f org\.monarch\.screensaver" \
  "$ROOT/bin/monarch-screensaver" "$ROOT/bin/monarch-system-lock"
! grep -F "pgrep -f org.monarch.screensaver" "$ROOT/bin/monarch-launch-screensaver"

mkdir -p "$TMP/bin" "$TMP/disabled/.local/state/monarch/toggles"
touch "$TMP/bin/tte" "$TMP/disabled/.local/state/monarch/toggles/screensaver-off"
chmod +x "$TMP/bin/tte"
if HOME="$TMP/disabled" PATH="$TMP/bin:$ROOT/bin:/usr/bin" \
  "$ROOT/bin/monarch-launch-screensaver" >/dev/null 2>&1; then
  echo "Disabled screensaver still launches on idle" >&2
  exit 1
fi

echo "Fresh installs launch and stop the screensaver on idle"
