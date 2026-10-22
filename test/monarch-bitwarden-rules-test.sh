#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$ROOT/default/niri/windows.kdl" <<'PY'
import pathlib
import re
import sys

config = pathlib.Path(sys.argv[1]).read_text()
rules = re.findall(r"window-rule \{(.*?)^\}", config, re.MULTILINE | re.DOTALL)
for app_id in ("Bitwarden", "bitwarden"):
  matching = [
    rule for rule in rules
    if any(re.search(pattern, app_id) for pattern in re.findall(r'app-id=r#"(.*?)"#', rule))
  ]
  assert matching, f"No rule matches {app_id}"
  assert any(
    'block-out-from "screencast"' in rule and "open-floating true" in rule
    for rule in matching
  ), f"{app_id} must float and be hidden from screen sharing"

print("ok - Arch and upstream Bitwarden builds float and stay hidden from screen sharing")
PY
