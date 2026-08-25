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

mkdir -p "$TMP/home/.config/noctalia"
cat >"$TMP/home/.config/noctalia/config.toml" <<'EOF'
[idle]
# v4's flat idle.{lockTimeout,screenOffTimeout,…} became named behaviours with
# their own timeouts, ordered by behavior_order. v4's idle.customCommands (the
# screensaver at 150s) has no equivalent here and is not ported.
behavior_order = ["lock", "screen-off"]

  [idle.behavior.lock]
action = "lock"
enabled = true
timeout = 300.0

  [idle.behavior.screen-off]
action = "screen_off"
enabled = true
timeout = 330.0
EOF

HOME="$TMP/home" MONARCH_PATH="$ROOT" bash "$ROOT/migrations/1787603337.sh" >/dev/null
assert_screensaver_idle "$TMP/home/.config/noctalia/config.toml"
grep -Fx 'timeout = 300.0' "$TMP/home/.config/noctalia/config.toml" >/dev/null
! grep -q 'has no equivalent here' "$TMP/home/.config/noctalia/config.toml"

echo "Existing installs gain the screensaver without losing idle settings"
