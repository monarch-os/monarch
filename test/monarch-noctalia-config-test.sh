#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

grep -Fqx 'clipboard_history_max_entries = 500' "$ROOT/config/noctalia/config.toml"
echo "Noctalia keeps the extended clipboard history"

grep -Fqx 'setup_wizard_enabled = false' "$ROOT/config/noctalia/config.toml"
echo "Noctalia skips its setup wizard on managed installs"

grep -q 'monarch/theme' "$ROOT/install/user/first-run/enable-noctalia-plugins.sh"
echo "Fresh installs enable the Monarch theme plugin"

grep -Fqx 'noctalia msg config-reload' "$ROOT/install/user/first-run/enable-noctalia-plugins.sh"
echo "Plugin activation reloads Noctalia through the v5 IPC"

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
