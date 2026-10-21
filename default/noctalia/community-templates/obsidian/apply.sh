#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
python3 - "${BASH_SOURCE[0]%/*}/rendered.css" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

home = Path.home()
css = Path(sys.argv[1]).read_bytes()
vaults = set()
registry = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')) / 'obsidian/obsidian.json'
if registry.exists():
  data = json.loads(registry.read_text())
  for vault in data.get('vaults', {}).values():
    path = vault.get('path') if isinstance(vault, dict) else None
    if isinstance(path, str):
      vaults.add(Path(path) / '.obsidian')
for current, directories, _ in os.walk(home):
  if '.obsidian' in directories:
    vaults.add(Path(current) / '.obsidian')
  directories[:] = [name for name in directories if not name.startswith('.')]
  if len(Path(current).relative_to(home).parts) >= 3:
    directories.clear()

def write_atomic(path, content):
  if path.is_symlink():
    raise ValueError(f'refusing to replace symlink {path}')
  path.parent.mkdir(parents=True, exist_ok=True)
  mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
  fd, name = tempfile.mkstemp(prefix='.monarch-theme-', dir=path.parent)
  try:
    with os.fdopen(fd, 'wb') as output:
      output.write(content)
      os.fchmod(output.fileno(), mode)
    os.replace(name, path)
  finally:
    Path(name).unlink(missing_ok=True)

failed = False
for vault in sorted(vaults):
  if not vault.is_dir():
    continue
  try:
    appearance = vault / 'appearance.json'
    for path in (vault, vault / 'snippets', vault / 'snippets/noctalia.css', appearance):
      if path.is_symlink():
        raise ValueError(f'refusing symlink {path}')
    settings = json.loads(appearance.read_text()) if appearance.exists() else {}
    if not isinstance(settings, dict):
      raise ValueError('invalid appearance settings')
    snippets = settings.get('enabledCssSnippets', [])
    if not isinstance(snippets, list):
      raise ValueError('invalid appearance settings')
    if 'noctalia' not in snippets:
      snippets.append('noctalia')
    settings['enabledCssSnippets'] = snippets
    write_atomic(vault / 'snippets/noctalia.css', css)
    write_atomic(appearance, (json.dumps(settings, indent=2) + '\n').encode())
  except (OSError, ValueError) as error:
    print(f'Obsidian theme: {vault}: {error}', file=sys.stderr)
    failed = True
sys.exit(1 if failed else 0)
PY
