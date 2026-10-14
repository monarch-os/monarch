#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
plugin = root / 'default/noctalia/plugins/monarch-agents'

def flatten(value, prefix=''):
  result = {}
  for key, item in value.items():
    name = prefix + key
    if isinstance(item, dict):
      result.update(flatten(item, name + '.'))
    else:
      assert isinstance(item, str)
      result[name] = item
  return result

catalogs = {lang: flatten(json.loads((plugin / f'translations/{lang}.json').read_text()))
            for lang in ('en', 'fr')}
assert catalogs['en'].keys() == catalogs['fr'].keys()
for key in catalogs['en']:
  assert set(re.findall(r'\{(\w+)\}', catalogs['en'][key])) == set(re.findall(r'\{(\w+)\}', catalogs['fr'][key]))
for source in plugin.glob('*.luau'):
  for key in re.findall(r'noctalia\.tr\("([^"]+)"', source.read_text()):
    assert key in catalogs['en'], (source, key)
with tempfile.TemporaryDirectory() as directory:
  path = Path(directory) / 'catalogs.lua'
  quote = lambda value: json.dumps(value, ensure_ascii=False)
  path.write_text('return {\n' + ',\n'.join(
    '[' + quote(lang) + '] = {\n' + ',\n'.join(
      '[' + quote(key) + '] = ' + quote(value) for key, value in entries.items()) + '\n}'
    for lang, entries in catalogs.items()) + '\n}\n')
  subprocess.run(['lua', str(root / 'test/monarch-agent-plugin-test.lua'), str(plugin), str(path)], check=True)
PY
