#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" MONARCH_PATH="$ROOT"
unset XDG_CONFIG_HOME
mkdir -p "$test_tmp/bin" "$HOME/.config/noctalia/colorschemes/Nord" \
  "$HOME/.config/herdr" "$HOME/.config/fastfetch"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/pkill"
ln -s "$ROOT/bin/monarch-refresh-config" "$test_tmp/bin/monarch-refresh-config"
chmod +x "$test_tmp/bin/pkill"
export PATH="$test_tmp/bin:/usr/bin"

cat >"$HOME/.config/herdr/config.toml" <<'EOF'
[keys]
prefix = "ctrl+a"
[terminal]
new_cwd = "home"
[theme.custom]
accent = "#abcdef"
EOF
cp "$HOME/.config/herdr/config.toml" "$test_tmp/herdr-original"
cat >"$HOME/.config/fastfetch/config.jsonc" <<'EOF'
// Keep my modules and formatting.
{"modules": ["custom", {"type": "command", "text": "theme=$(jq -r '.colorSchemes.predefinedScheme // \"Monarch\"' ~/.config/noctalia/settings.json 2>/dev/null); echo -e \"$theme CUSTOM\""}]}
EOF
cp "$HOME/.config/fastfetch/config.jsonc" "$test_tmp/fastfetch-original"
cat >"$HOME/.config/noctalia/settings.json" <<'EOF'
{"colorSchemes": {"predefinedScheme": "Nord", "darkMode": false},
 "bar": {"position": "left"},
 "idle": {"enabled": true, "lockTimeout": 0, "screenOffTimeout": 600,
          "suspendTimeout": 900,
          "customCommands": "[{\"timeout\":90,\"command\":\"monarch-launch-screensaver\",\"resumeCommand\":\"\"}]"}}
EOF
cp "$ROOT/config/noctalia/palettes/Monarch.json" "$HOME/.config/noctalia/colorschemes/Nord/Nord.json"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"

cmp -s "$test_tmp/herdr-original" "$HOME/.config/herdr/config.toml" || fail "custom Herdr settings survive"
grep -qF 'Keep my modules and formatting.' "$HOME/.config/fastfetch/config.jsonc"
grep -qF 'CUSTOM' "$HOME/.config/fastfetch/config.jsonc"
grep -qF 'noctalia msg color-scheme-get' "$HOME/.config/fastfetch/config.jsonc" || fail "Fastfetch switches only its legacy theme reader"
cmp -s "$test_tmp/fastfetch-original" "$HOME/.config/fastfetch/config.jsonc.bak.monarch-v5"
python3 <<'PY'
import os
import pathlib
import tomllib

config = pathlib.Path(os.environ["HOME"]) / ".config/noctalia"
prefs = tomllib.loads((config / "monarch-v4.toml").read_text())
assert prefs["theme"] == {"mode": "light", "source": "custom", "custom_palette": "V4-Nord"}
bar = tomllib.loads((config / "zz-monarch-bar-position.toml").read_text())
assert bar["bar"]["default"]["position"] == "left"
idle = prefs["idle"]["behavior"]
assert idle["lock"]["timeout"] == 0 and idle["lock"]["enabled"] is False
assert idle["screen-off"]["timeout"] == 600
assert idle["suspend"]["action"] == "lock_and_suspend"
assert idle["suspend"]["timeout"] == 900
assert idle["screensaver"]["timeout"] == 90
assert (config / "palettes/V4-Nord.json").read_bytes() == (
  pathlib.Path(os.environ["MONARCH_PATH"]) / "config/noctalia/palettes/Monarch.json"
).read_bytes()
PY
[[ $("$ROOT/bin/monarch-bar-position") == left ]] || fail "bar position command sees the migrated position"
pass "custom app settings, compatible preferences and colliding palettes survive V4 migration"

archive="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
[[ -f $archive/settings.json && -f $archive/colorschemes/Nord/Nord.json ]]
printf '[theme]\nmode = "dark"\n' >"$HOME/.config/noctalia/monarch-v4.toml"
printf '[bar.default]\nposition = "right"\n' >"$HOME/.config/noctalia/zz-monarch-bar-position.toml"
printf 'existing-v5-palette\n' >"$HOME/.config/noctalia/palettes/V4-Nord.json"
rm "$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
grep -qx 'mode = "dark"' "$HOME/.config/noctalia/monarch-v4.toml"
[[ $("$ROOT/bin/monarch-bar-position") == right ]]
[[ $(<"$HOME/.config/noctalia/palettes/V4-Nord.json") == existing-v5-palette ]]
pass "interrupted migration resumes from the archive without overwriting V5 edits"

export HOME="$test_tmp/disabled"
mkdir -p "$HOME/.config/noctalia"
printf '%s\n' '{"idle":{"enabled":false},"colorSchemes":{"useWallpaperColors":true}}' \
  >"$HOME/.config/noctalia/settings.json"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
python3 <<'PY'
import os
import pathlib
import tomllib

config = pathlib.Path(os.environ["HOME"]) / ".config/noctalia/monarch-v4.toml"
prefs = tomllib.loads(config.read_text())
assert prefs["theme"]["source"] == "wallpaper"
assert all(not item["enabled"] for item in prefs["idle"]["behavior"].values())
assert {"lock", "screen-off", "screensaver"} <= prefs["idle"]["behavior"].keys()
PY
cmp "$ROOT/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
cmp "$ROOT/config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
pass "disabled idle remains disabled and missing app configs receive defaults"

export HOME="$test_tmp/invalid"
mkdir -p "$HOME/.config/noctalia"
printf 'invalid-json\n' >"$HOME/.config/noctalia/settings.json"
if bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh" >/dev/null 2>&1; then
  fail "invalid settings must not silently complete migration"
fi
[[ -f $HOME/.config/noctalia/settings.json ]]
[[ ! -e $HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia ]]
pass "unreadable legacy settings stay in place and keep migration pending"

export HOME="$test_tmp/stock"
mkdir -p "$HOME/.config/herdr"
sed -e 's/{{colors.surface_container.default.hex}}/#112233/' \
  -e 's/{{colors.primary.default.hex}}/#ABCDEF/' \
  "$ROOT/test/fixtures/noctalia-v4/herdr.toml" >"$HOME/.config/herdr/config.toml"
cp "$HOME/.config/herdr/config.toml" "$test_tmp/stock-original"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
cmp "$ROOT/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
cmp "$test_tmp/stock-original" "$HOME/.config/herdr/config.toml.bak.monarch-v5"
pass "recognized V4 Herdr output moves to terminal colors with an original backup"

export HOME="$test_tmp/symlinks"
mkdir -p "$HOME/.config/herdr" "$HOME/.config/fastfetch" "$HOME/.config/noctalia"
ln -s "$test_tmp/stock-original" "$HOME/.config/herdr/config.toml"
ln -s missing "$HOME/.config/fastfetch/config.jsonc"
ln -s missing "$HOME/.config/noctalia/monarch-v4.toml"
printf '%s\n' '{"colorSchemes":{"darkMode":false}}' >"$HOME/.config/noctalia/settings.json"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
[[ -L $HOME/.config/herdr/config.toml && -L $HOME/.config/fastfetch/config.jsonc ]]
[[ -L $HOME/.config/noctalia/monarch-v4.toml ]]
cmp "$test_tmp/stock-original" "$HOME/.config/herdr/config.toml"
pass "user-managed and broken symlinks are left intact"

export HOME="$test_tmp/backup-conflict"
mkdir -p "$HOME/.config/fastfetch"
cp "$test_tmp/fastfetch-original" "$HOME/.config/fastfetch/config.jsonc"
printf 'keep-backup\n' >"$HOME/.config/fastfetch/config.jsonc.bak.monarch-v5"
if bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh" >/dev/null 2>&1; then
  fail "a conflicting original backup keeps migration pending"
fi
cmp "$test_tmp/fastfetch-original" "$HOME/.config/fastfetch/config.jsonc"
[[ $(<"$HOME/.config/fastfetch/config.jsonc.bak.monarch-v5") == keep-backup ]]
[[ ! -e $HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia ]]
mv "$HOME/.config/fastfetch/config.jsonc.bak.monarch-v5" "$HOME/previous-backup"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
cmp "$test_tmp/fastfetch-original" "$HOME/.config/fastfetch/config.jsonc.bak.monarch-v5"
pass "backup collisions preserve both files and permit a retry after resolution"

export HOME="$test_tmp/custom-idle"
mkdir -p "$HOME/.config/noctalia"
python3 <<'PY'
import json
import os
from pathlib import Path

config = Path(os.environ["HOME"]) / ".config/noctalia"
settings = {
  "colorSchemes": {"predefinedScheme": "Dracula", "darkMode": True},
  "idle": {"customCommands": [{"timeout": 1.5, "command": "echo 'héllo' \"$HOME\"", "resumeCommand": "true"}]},
}
(config / "settings.json").write_text(json.dumps(settings))
PY
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-noctalia.sh"
python3 <<'PY'
import os
from pathlib import Path
import tomllib

config = Path(os.environ["HOME"]) / ".config/noctalia"
prefs = tomllib.loads((config / "monarch-v4.toml").read_text())
assert prefs["theme"] == {"source": "builtin", "builtin": "Dracula", "mode": "dark"}
idle = prefs["idle"]["behavior"]
assert idle["screensaver"]["enabled"] is False
assert idle["v4-command-0"] == {
  "action": "command", "timeout": 1.5, "enabled": True,
  "command": "echo 'héllo' \"$HOME\"", "resume_command": "true",
}
PY
pass "builtin palettes and custom idle command data round-trip into valid TOML"
