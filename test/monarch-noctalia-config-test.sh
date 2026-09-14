#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

grep -Fqx 'clipboard_history_max_entries = 500' "$ROOT/config/noctalia/config.toml"
echo "Noctalia keeps the extended clipboard history"

grep -Fqx 'setup_wizard_enabled = false' "$ROOT/config/noctalia/config.toml"
echo "Noctalia skips its setup wizard on managed installs"

grep -Fqx 'label_source = "name"' "$ROOT/config/noctalia/monarch-workspaces.toml"
grep -Fqx 'max_label_chars = 10' "$ROOT/config/noctalia/monarch-workspaces.toml"
grep -Fqx 'focused_output_only = true' "$ROOT/config/noctalia/monarch-workspaces.toml"
grep -Fqx 'occupied_color = "on_primary"' "$ROOT/config/noctalia/monarch-workspaces.toml"
echo "Noctalia displays persistent Niri workspace names"

example="$ROOT/config/noctalia/user-templates.toml.example"
EXAMPLE="$example" python3 <<'PY'
import os
import tomllib

with open(os.environ["EXAMPLE"], "rb") as source:
  entry = tomllib.load(source)["theme"]["templates"]["user"]["my_app"]

assert entry == {
  "enabled": False,
  "input_path": "$XDG_CONFIG_HOME/noctalia/templates/my-app.conf.tpl",
  "output_path": "$XDG_CONFIG_HOME/my-app/theme.conf",
}
PY
echo "Noctalia ships an inert data-only user-template example"

HERDR_REGISTRATION="$ROOT/config/noctalia/monarch-herdr.toml" \
HERDR_TEMPLATE="$ROOT/config/noctalia/templates/herdr.toml" python3 <<'PY'
import os
import tomllib

with open(os.environ["HERDR_REGISTRATION"], "rb") as source:
  entry = tomllib.load(source)["theme"]["templates"]["user"]["herdr"]

assert entry == {
  "enabled": True,
  "input_path": "$XDG_CONFIG_HOME/noctalia/templates/herdr.toml",
  "output_path": "$XDG_CONFIG_HOME/herdr/config.toml",
  "post_hook": "monarch-restart-herdr",
}

template = open(os.environ["HERDR_TEMPLATE"]).read()
assert 'panel_bg = "{{colors.surface_container.default.hex}}"' in template
assert 'accent = "{{colors.primary.default.hex}}"' in template
PY
echo "Noctalia renders and reloads the Herdr theme"

[[ ! -e $ROOT/config/herdr/config.toml ]]
echo "Herdr has no second packaged configuration source"

herdr_bin="$TMP/herdr-bin"
herdr_log="$TMP/herdr-refresh.log"
mkdir -p "$herdr_bin"
cat >"$herdr_bin/monarch-refresh-config" <<'EOF'
#!/bin/bash
printf 'refresh %s\n' "$*" >>"$HERDR_REFRESH_LOG"
EOF
cat >"$herdr_bin/noctalia" <<'EOF'
#!/bin/bash
printf 'noctalia %s\n' "$*" >>"$HERDR_REFRESH_LOG"
EOF
chmod +x "$herdr_bin/"*
HERDR_REFRESH_LOG="$herdr_log" PATH="$herdr_bin:/usr/bin" \
  "$ROOT/bin/monarch-refresh-herdr"
grep -Fqx 'refresh noctalia/templates/herdr.toml' "$herdr_log"
grep -Fqx 'noctalia msg templates-apply' "$herdr_log"
echo "Herdr refresh restores and renders its only source"

mkdir -p "$TMP/bin"
printf '%s\n' '#!/bin/bash' 'exit 23' >"$TMP/bin/monarch-refresh-config"
chmod +x "$TMP/bin/monarch-refresh-config"
if PATH="$TMP/bin:/usr/bin" "$ROOT/bin/monarch-refresh-noctalia" >/dev/null 2>&1; then
  echo "Noctalia refresh hid a configuration failure" >&2
  exit 1
fi
echo "Noctalia refresh propagates configuration failures"

refresh_home="$TMP/refresh-home"
refresh_source="$TMP/refresh-source"
mkdir -p "$refresh_home/.config/noctalia" "$refresh_source/config/noctalia"
printf '%s\n' user-config >"$refresh_home/.config/noctalia/config.toml"
if HOME="$refresh_home" MONARCH_PATH="$refresh_source" \
  "$ROOT/bin/monarch-refresh-config" noctalia/config.toml >/dev/null 2>&1; then
  echo "Config refresh hid a failed packaged-default copy" >&2
  exit 1
fi
[[ $(<"$refresh_home/.config/noctalia/config.toml") == "user-config" ]]
if compgen -G "$refresh_home/.config/noctalia/config.toml.bak.*" >/dev/null; then
  echo "Config refresh backed up a file before validating its packaged default" >&2
  exit 1
fi
echo "Config refresh propagates packaged-default copy failures"
