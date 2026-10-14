import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
path = Path(os.environ['CODEXBAR_CONFIG'])
data = json.loads(path.read_text()) if path.exists() else [
  {'provider': name, 'displayName': title, 'enabled': False}
  for name, title in [('claude', 'Claude'), ('codex', 'Codex'), ('synthetic', 'Synthetic'), ('openrouter', 'OpenRouter')]
]
with open(os.environ['TEST_CALLS'], 'a') as log:
  log.write(json.dumps(args) + '\n')

action = args[1]
if action == 'providers':
  print(json.dumps(data))
  sys.exit(0)
provider = args[args.index('--provider') + 1]
entry = next((entry for entry in data if entry['provider'] == provider), None)
if not entry:
  sys.exit(1)
if action == 'set-api-key':
  if provider not in ('synthetic', 'openrouter') or '--stdin' not in args:
    sys.exit(1)
  key = sys.stdin.read().strip()
  if os.environ.get('TEST_KEY_FAILURE') == 'true' or not key:
    sys.exit(1)
  entry['apiKey'] = key
  entry['enabled'] = True
elif action == 'set-source':
  entry['source'] = args[args.index('--source') + 1]
else:
  entry['enabled'] = action == 'enable'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data))
path.chmod(0o600)
print('Config updated')
