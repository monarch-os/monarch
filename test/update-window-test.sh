#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export MONARCH_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"
export MONARCH_LANGUAGE=en

action=$(monarch-menu --tree | jq -r '.[] | select(.id == "update.monarch") | .action')
[[ $action == "monarch-launch-floating-terminal-with-presentation --app-id=org.monarch.update monarch-update" ]] || {
  echo "not ok - update menu must use its dedicated window identity" >&2
  exit 1
}

grep -Fq ' --app-id=org.monarch.update monarch-update"' "$ROOT/default/noctalia/plugins/monarch-indicators/monarch-update.luau"

python3 - "$ROOT/default/niri/windows.kdl" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
rule = re.search(r'window-rule\s*\{\s*match app-id="org\.monarch\.update"(.*?)\n\}', text, re.S)
assert rule, "update window needs a dedicated Niri rule"
for setting in ('open-floating true', 'default-column-width { fixed 875; }', 'default-window-height { fixed 600; }'):
  assert setting in rule[1], f"missing update window setting: {setting}"
PY

echo "ok - menu and bar open updates in an 875 x 600 floating window"
