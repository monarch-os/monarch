#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

grep -Fqx 'clipboard_history_max_entries = 500' "$ROOT/config/noctalia/config.toml"
echo "Noctalia keeps the extended clipboard history"

grep -Fqx 'setup_wizard_enabled = false' "$ROOT/config/noctalia/config.toml"
echo "Noctalia skips its setup wizard on managed installs"

grep -q 'monarch/theme' "$ROOT/install/user/first-run/enable-noctalia-plugins.sh"
echo "Fresh installs enable the Monarch theme plugin"

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
