#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

python3 <<'PY'
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

root = Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as directory:
  fixture = Path(directory)
  tools = fixture / 'bin'
  tools.mkdir()
  home = fixture / 'home'
  home.mkdir()
  runtime = fixture / 'runtime'
  runtime.mkdir()
  wrapper = fixture / 'default/monarch/sudo-no-update/sudo'
  wrapper.parent.mkdir(parents=True)

  def executable(path, text):
    path.write_text(text)
    path.chmod(0o755)

  sudo = tools / 'sudo'
  executable(sudo, '''#!/usr/bin/python3
import json, os, subprocess, sys, time
from pathlib import Path
args = sys.argv[1:]
state = Path(os.environ['SUDO_STATE'])
with open(os.environ['EVENTS'], 'a') as log:
  log.write(json.dumps(['sudo', os.getpid(), args]) + '\\n')
if args == ['-k']:
  if Path(os.environ['FAIL_REVOKE']).exists(): sys.exit(19)
  state.unlink(missing_ok=True)
  sys.exit(0)
if args == ['/usr/bin/true'] and os.environ.get('FAIL_AUTHORIZE'): sys.exit(5)
no_update = bool(args and args[0] == '-N')
if no_update: args.pop(0)
noninteractive = bool(args and args[0] == '-n')
if noninteractive: args.pop(0)
valid = state.exists() and time.monotonic() - float(state.read_text()) < 0.3
if noninteractive and not valid: sys.exit(1)
if not no_update: state.write_text(str(time.monotonic()))
sys.exit(subprocess.call(args))
''')
  executable(wrapper, (root / 'default/monarch/sudo-no-update/sudo').read_text().replace('/usr/bin/sudo', str(sudo)))
  executable(tools / 'monarch-update', (root / 'bin/monarch-update').read_text().replace('/usr/bin/sudo', str(sudo)))
  shutil.copy2(root / 'bin/monarch-update-lock', tools / 'monarch-update-lock')
  shutil.copy2(root / 'bin/monarch-update-aur-pkgs', tools / 'monarch-update-aur-pkgs')
  executable(tools / 'sleep', '#!/bin/bash\nif [[ $1 == 60 ]]; then printf "%s %s\\n" "$$" "$PPID" >> "$KEEPALIVE_PIDS"; exec /usr/bin/sleep 0.05; fi\nexec /usr/bin/sleep "$@"\n')
  steps = ('requires-free-space', 'pkg-prune', 'git', 'keyring', 'system-pkgs', 'orphan-pkgs', 'analyze-logs', 'stay-awake', 'restart')
  script = '''#!/usr/bin/python3
import json, os, subprocess, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['EVENTS'], 'a') as log: log.write(json.dumps([name, sys.argv[1:]]) + '\\n')
if name == os.environ.get('FAIL_STAGE'): sys.exit(17)
if name == 'monarch-update-system-pkgs':
  Path(os.environ['ENTERED']).touch()
  time.sleep(10 if os.environ.get('BLOCK') else 0.7)
if name == 'monarch-reconcile' or (name == 'monarch-update-restart' and '--services-only' in sys.argv):
  assert os.environ.get('MONARCH_UPDATE_SUDO_SESSION') == '1'
  sys.exit(subprocess.call(['sudo', '-n', '/usr/bin/true']))
if name == 'monarch-hook' and os.environ.get('BREAK_REVOKE'): Path(os.environ['FAIL_REVOKE']).touch()
if name == 'monarch-update-restart' and '--reboot-only' in sys.argv:
  assert not Path(os.environ['SUDO_STATE']).exists()
  assert 'MONARCH_UPDATE_SUDO_SESSION' not in os.environ
'''
  for name in [*('monarch-update-' + step for step in steps), 'monarch-reconcile', 'monarch-hook', 'monarch-snapshot']:
    executable(tools / name, script)
  executable(tools / 'pacman', '#!/bin/bash\nexit 0\n')
  executable(tools / 'monarch-pkg-aur-accessible', '#!/bin/bash\nexit 0\n')
  executable(tools / 'yay', '''#!/usr/bin/python3
import json, os, shutil, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
wrapper = args[args.index('--sudo') + 1]
assert '--sudoloop=false' in args
assert shutil.which('sudo') == wrapper
assert not Path(os.environ['SUDO_STATE']).exists()
assert 'MONARCH_UPDATE_SUDO_SESSION' not in os.environ
with open(os.environ['EVENTS'], 'a') as log: log.write(json.dumps(['yay', args]) + '\\n')
for _ in range(2):
  subprocess.run([wrapper, '/usr/bin/true'], check=True)
  assert not Path(os.environ['SUDO_STATE']).exists()
sys.exit(int(os.environ.get('YAY_EXIT', '0')))
''')
  env = {key: value for key, value in os.environ.items() if key not in ('BASH_ENV', 'ENV', 'MONARCH_UPDATE_LOCKED', 'MONARCH_UPDATE_SUDO_SESSION', 'MONARCH_SUDO_NO_UPDATE')}
  env.update(HOME=str(home), MONARCH_PATH=str(fixture), MONARCH_UPDATE_LOGGED='1', XDG_RUNTIME_DIR=str(runtime),
    PATH=str(tools) + ':' + str(root / 'bin') + ':' + os.environ['PATH'], SUDO_STATE=str(fixture / 'sudo-state'),
    EVENTS=str(fixture / 'events'), ENTERED=str(fixture / 'entered'), FAIL_REVOKE=str(fixture / 'fail-revoke'), KEEPALIVE_PIDS=str(fixture / 'keepalive-pids'))

  def run(extra=None):
    for name in ('sudo-state', 'events', 'entered', 'fail-revoke', 'keepalive-pids'):
      (fixture / name).unlink(missing_ok=True)
    result = subprocess.run([str(tools / 'monarch-update'), '-y'], env={**env, **(extra or {})}, capture_output=True, text=True, timeout=15)
    events = [json.loads(line) for line in (fixture / 'events').read_text().splitlines()]
    if not (extra or {}).get('BREAK_REVOKE'):
      assert not (fixture / 'sudo-state').exists(), result
    sudo_pids = {event[1] for event in events if event[0] == 'sudo'}
    time.sleep(0.1)
    for pid in sudo_pids:
      assert not Path('/proc', str(pid)).exists(), ('sudo child survived', pid)
    if (fixture / 'keepalive-pids').exists():
      for pid in (fixture / 'keepalive-pids').read_text().split():
        assert not Path('/proc', pid).exists(), ('keepalive or sleep survived', pid)
    return result, events

  result, events = run()
  assert result.returncode == 0, result.stderr
  assert any(event[0] == 'sudo' and event[2] == ['-n', '/usr/bin/true'] for event in events)
  assert sum(event[0] == 'sudo' and event[2] == ['/usr/bin/true'] for event in events) == 1
  stages = [event[0] for event in events]
  assert stages.index('monarch-update-orphan-pkgs') < stages.index('monarch-hook') < stages.index('yay')
  assert stages.index('monarch-update-restart') < stages.index('yay')
  assert sum(event[0] == 'sudo' and event[2] == ['-N', '/usr/bin/true'] for event in events) == 2
  print('ok - long updates share one authorization and AUR sudo calls never refresh it')
  for stage in ('monarch-update-system-pkgs', 'monarch-reconcile', 'monarch-update-restart'):
    result, events = run({'FAIL_STAGE': stage})
    assert result.returncode == 17, result
    assert not any(event[0] == 'yay' for event in events)
    assert ['monarch-update-stay-awake', ['stop']] in events
  result, events = run({'YAY_EXIT': '23'})
  assert result.returncode == 23, result
  assert ['monarch-update-stay-awake', ['stop']] in events
  print('ok - system and AUR failures revoke authorization and release inhibition')
  result, events = run({'FAIL_AUTHORIZE': '1'})
  assert result.returncode == 1, result
  assert not any(event[0] == 'monarch-update-pkg-prune' for event in events)
  print('ok - failed authorization prevents the privileged transaction')
  result, events = run({'BREAK_REVOKE': '1'})
  assert result.returncode != 0 and not any(event[0] == 'yay' for event in events)
  print('ok - failed revocation prevents AUR execution')
  (fixture / 'fail-revoke').unlink()
  (fixture / 'entered').unlink(missing_ok=True)
  proc = subprocess.Popen([str(tools / 'monarch-update'), '-y'], env={**env, 'BLOCK': '1'}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
  try:
    deadline = time.monotonic() + 5
    while not (fixture / 'entered').exists() and proc.poll() is None and time.monotonic() < deadline:
      time.sleep(0.02)
    assert (fixture / 'entered').exists()
    os.killpg(proc.pid, signal.SIGTERM)
    assert proc.wait(timeout=5) in (143, -signal.SIGTERM)
    deadline = time.monotonic() + 3
    while (fixture / 'sudo-state').exists() and time.monotonic() < deadline:
      time.sleep(0.02)
    assert not (fixture / 'sudo-state').exists()
    subprocess.run([str(tools / 'monarch-update-lock'), 'run', 'true'], env=env, check=True)
  finally:
    if proc.poll() is None:
      os.killpg(proc.pid, signal.SIGKILL)
      proc.wait()
  print('ok - SIGTERM revokes authorization and frees the update lock')
  poison = fixture / 'poison'
  executable(fixture / 'bash-env', 'touch ' + str(poison) + '\n')
  subprocess.run([str(wrapper), '/usr/bin/true'], env={**env, 'BASH_ENV': str(fixture / 'bash-env')}, check=True)
  assert not poison.exists()
  unsafe = subprocess.run(['bash', str(wrapper), '/usr/bin/true'], env=env, capture_output=True)
  assert unsafe.returncode == 126
  print('ok - the no-update sudo wrapper rejects unsafe shell startup')
  modules = fixture / 'modules/running'
  modules.mkdir(parents=True)
  (modules / 'vmlinuz').touch()
  restart = tools / 'real-restart'
  executable(restart, (root / 'bin/monarch-update-restart').read_text().replace('/usr/lib/modules', str(fixture / 'modules')))
  executable(tools / 'uname', '#!/bin/bash\necho running\n')
  executable(tools / 'gum', '#!/bin/bash\necho prompt >> "$RESTART_LOG"\nexit 1\n')
  executable(tools / 'monarch-restart-example', '#!/bin/bash\necho service >> "$RESTART_LOG"\n')
  executable(tools / 'monarch-state', '#!/bin/bash\nrm -f "$HOME/.local/state/monarch/$2"\n')
  state = home / '.local/state/monarch'
  state.mkdir(parents=True)
  (state / 'restart-example-required').touch()
  (state / 'reboot-required').touch()
  restart_log = fixture / 'restart-log'
  restart_env = {**env, 'RESTART_LOG': str(restart_log)}
  subprocess.run([str(restart), '--services-only'], env=restart_env, check=True)
  assert restart_log.read_text() == 'service\n'
  (state / 'restart-example-required').touch()
  subprocess.run([str(restart), '--reboot-only'], env={**restart_env, 'MONARCH_UPDATE_UNATTENDED': '1'}, check=True)
  assert (state / 'restart-example-required').exists()
  assert restart_log.read_text() == 'service\n'
  print('ok - service restarts are separate and unattended reboot checks never prompt')
PY
