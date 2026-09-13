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
! grep -R -n "pkill -f org\.monarch\.screensaver" \
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

cat >"$TMP/bin/idle-recorder" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >>"$IDLE_TEST_LOG"
EOF
chmod +x "$TMP/bin/idle-recorder"
for command in noctalia pgrep pkill 1password monarch-brightness-keyboard niri; do
  ln -s idle-recorder "$TMP/bin/$command"
done
export IDLE_TEST_LOG="$TMP/idle.log"
PATH="$TMP/bin:$ROOT/bin:/usr/bin" python3 - "$ROOT" <<'PY'
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tomllib

root = Path(sys.argv[1])
defaults = tomllib.loads((root / "config/noctalia/config.toml").read_text())["idle"]["behavior"]
spec = importlib.util.spec_from_file_location(
  "noctalia_config", root / "install/reconcile/schema/1-to-2/noctalia-config.py"
)
module = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(module)
log = Path(os.environ["IDLE_TEST_LOG"])

def execute(behavior, resume=False):
  assert behavior["action"] == "command", "native idle actions ignore the configured Monarch command"
  log.write_text("")
  subprocess.run(["bash", "-c", behavior["resume_command" if resume else "command"]],
                 check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  return log.read_text().splitlines()

def check_actions(behaviors):
  calls = execute(behaviors["lock"])
  assert "noctalia msg session lock" in calls
  assert "1password --lock" in calls
  assert "pkill -f [o]rg.monarch.screensaver" in calls
  assert "niri msg action power-off-monitors" not in calls
  calls = execute(behaviors["screen-off"])
  assert "monarch-brightness-keyboard off" in calls
  assert "niri msg action power-off-monitors" in calls
  calls = execute(behaviors["screen-off"], resume=True)
  assert "monarch-brightness-keyboard restore" in calls
  assert "niri msg action power-on-monitors" in calls

check_actions(defaults)
print("ok - shipped idle actions lock applications and restore screen and keyboard power")

def migrated(idle):
  prefs = module.preferences({"idle": idle}, {}, root)
  overlay = tomllib.loads(module.toml(prefs).decode())["idle"]["behavior"]
  return {name: {**defaults.get(name, {}), **values} for name, values in overlay.items()}

stock = {"lockTimeout": 300, "screenOffTimeout": 330,
         "lockCommand": "MONARCH_LOCK_ONLY=true monarch-system-lock",
         "screenOffCommand": "monarch-brightness-keyboard off",
         "resumeScreenOffCommand": "monarch-system-wake"}
check_actions(migrated(stock))
print("ok - migrated V4 idle actions retain the complete lock and power behavior")

custom = migrated({**stock, "lockCommand": "noctalia custom-lock 'with spaces'",
                   "screenOffCommand": "noctalia custom-off; false",
                   "resumeScreenOffCommand": "noctalia custom-resume"})
assert execute(custom["lock"]) == ["noctalia custom-lock with spaces"]
assert execute(custom["screen-off"]) == ["noctalia custom-off", "niri msg action power-off-monitors"]
assert execute(custom["screen-off"], resume=True) == ["niri msg action power-on-monitors", "noctalia custom-resume"]
print("ok - custom V4 commands survive migration without disabling display power management")
PY
