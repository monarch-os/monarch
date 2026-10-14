#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json
import contextlib
import io
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from unittest.mock import patch

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

bridge = (root / 'bin/monarch-agent-usage-fetch').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
result = subprocess.CompletedProcess([], 1, '[{"provider":"synthetic"}]', 'private diagnostics')
with patch('subprocess.run', return_value=result) as run:
  output = io.StringIO()
  with contextlib.redirect_stdout(output):
    exec(compile(bridge, 'usage-fetch', 'exec'), {})
  assert run.call_args.kwargs['timeout'] >= 90
  assert json.loads(output.getvalue()) == {'providers': [{'provider': 'synthetic'}], 'ok': False}
  assert 'private diagnostics' not in output.getvalue()
with patch('subprocess.run', side_effect=subprocess.TimeoutExpired('codexbar', 120)):
  output = io.StringIO()
  with contextlib.redirect_stdout(output):
    exec(compile(bridge, 'usage-fetch', 'exec'), {})
  assert json.loads(output.getvalue()) == {'providers': [], 'ok': False}
print('CodexBar streaming bridge tests passed')
PY
