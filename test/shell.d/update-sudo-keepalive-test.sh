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
import sys
import tempfile
import time

root = Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as directory:
  fixture = Path(directory)
  trusted_root = fixture / 'runtime-tree'
  tools = trusted_root / 'bin'
  tools.mkdir(parents=True)
  home = fixture / 'home'
  home.mkdir()
  runtime = fixture / 'runtime'
  runtime.mkdir()
  wrapper = trusted_root / 'default/monarch/sudo-no-update/sudo'
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
if not no_update:
  temporary = state.with_name(state.name + '.' + str(os.getpid()))
  temporary.write_text(str(time.monotonic()))
  temporary.replace(state)
sys.exit(subprocess.call(args))
''')
  executable(wrapper, (root / 'default/monarch/sudo-no-update/sudo').read_text().replace('/usr/bin/sudo', str(sudo)))
  trusted_sleep = fixture / 'trusted-sleep'
  trust_stat = fixture / 'trust-stat'
  executable(trust_stat, '''#!/usr/bin/python3
import os, subprocess, sys
from pathlib import Path
path = Path(sys.argv[-1])
tree = Path(__file__).parent / 'runtime-tree'
if path == tree or tree in path.parents:
  mode = subprocess.check_output(['/usr/bin/stat', '-Lc', '%a', '--', str(path)], text=True).strip()
  print(('1' if os.environ.get('UNTRUSTED_OWNER') else '0') + ' ' + mode)
else:
  mode = subprocess.check_output(['/usr/bin/stat', '-Lc', '%a', '--', str(path)], text=True).strip() if Path(__file__).parent in path.parents else '755'
  print(('1' if os.environ.get('UNTRUSTED_PARENT') else '0') + ' ' + mode)
''')
  executable(tools / 'monarch-update', (root / 'bin/monarch-update').read_text().replace('/usr/bin/sudo', str(sudo)).replace('/usr/bin/sleep', str(trusted_sleep)).replace('/usr/bin/stat', str(trust_stat)).replace('-uid 0', '-uid ' + str(os.getuid())).replace('runtime_root=/usr/share/monarch', 'runtime_root=' + str(fixture / 'missing-packaged-runtime')))
  shutil.copy2(root / 'bin/monarch-update-lock', tools / 'monarch-update-lock')
  shutil.copy2(root / 'bin/monarch-update-aur-pkgs', tools / 'monarch-update-aur-pkgs')
  reconcile = trusted_root / 'install/reconcile'
  reconcile.mkdir(parents=True)
  for name in ('mise.sh', 'mise-work-path.py'):
    shutil.copy2(root / 'install/reconcile' / name, reconcile / name)
  executable(tools / 'mise', '#!/bin/bash\nexit 0\n')
  restart = tools / 'real-restart'
  executable(restart, (root / 'bin/monarch-update-restart').read_text().replace('/usr/bin/sudo', str(sudo)).replace('/usr/lib/modules', str(fixture / 'modules')))
  state = home / '.local/state/monarch'
  state.mkdir(parents=True)
  executable(tools / 'monarch-state', '#!/bin/bash\nrm -f "$HOME/.local/state/monarch/$2"\n')
  sleep_fixture = '#!/bin/bash\nif [[ $1 == 60 ]]; then printf "%s\\n" "$$" >> "$KEEPALIVE_PIDS"; (( PPID == 1 )) || printf "%s\\n" "$PPID" >> "$KEEPALIVE_PIDS"; exec /usr/bin/sleep 0.05; fi\nexec /usr/bin/sleep "$@"\n'
  executable(trusted_sleep, sleep_fixture)
  executable(tools / 'sleep', '#!/bin/bash\nif [[ ${POISON_PATH_SLEEP:-0} == 1 ]]; then "' + str(sudo) + '" -n /usr/bin/true && touch "$SLEEP_POISON"; fi\nexec "' + str(trusted_sleep) + '" "$@"\n')
  steps = ('requires-free-space', 'pkg-prune', 'git', 'keyring', 'system-pkgs', 'orphan-pkgs', 'stay-awake', 'restart')
  script = '''#!/usr/bin/python3
import json, os, subprocess, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['EVENTS'], 'a') as log: log.write(json.dumps([name, sys.argv[1:]]) + '\\n')
if name == os.environ.get('FAIL_STAGE'): sys.exit(17)
if name == 'monarch-update-system-pkgs':
  Path(os.environ['ENTERED']).touch()
  time.sleep(10 if os.environ.get('BLOCK') else 0.7)
if name == 'monarch-update-pkg-prune':
  assert 'MONARCH_PACCACHE_BIN' not in os.environ
if name == 'monarch-update-keyring':
  subprocess.run(['monarch-pkg-present', 'monarch-keyring'], check=True)
if name == 'monarch-reconcile':
  assert os.environ.get('MONARCH_UPDATE_SUDO_SESSION') == '1'
  assert not any(key.startswith('BASH_FUNC_') for key in os.environ)
  assert 'BASH_ENV' not in os.environ and 'ENV' not in os.environ
  assert os.environ['MONARCH_PATH'] == str(Path(sys.argv[0]).parent.parent)
  assert os.environ['MONARCH_RUNTIME_ROOT'] == os.environ['MONARCH_PATH']
  assert 'MONARCH_PACCACHE_BIN' not in os.environ
  if os.environ.get('RECONCILE_PYTHON'):
    subprocess.run(['/bin/bash', '-c', 'source "$MONARCH_PATH/install/reconcile/mise.sh"'], check=True)
  if os.environ.get('BREAK_REVOKE'): Path(os.environ['FAIL_REVOKE']).touch()
  sys.exit(subprocess.call(['sudo', '-n', '/usr/bin/true']))
if name == 'monarch-update-restart' and '--services-only' in sys.argv:
  assert not Path(os.environ['SUDO_STATE']).exists()
  assert 'MONARCH_UPDATE_SUDO_SESSION' not in os.environ
  sys.exit(subprocess.call([os.environ['REAL_RESTART'], '--services-only']))
if name == 'monarch-update-restart' and '--reboot-only' in sys.argv:
  assert not Path(os.environ['SUDO_STATE']).exists()
  assert 'MONARCH_UPDATE_SUDO_SESSION' not in os.environ
  print('reboot check')
'''
  for name in [*('monarch-update-' + step for step in steps), 'monarch-reconcile', 'monarch-snapshot']:
    executable(tools / name, script)
  shutil.copy2(root / 'bin/monarch-hook', tools / 'real-hook')
  executable(tools / 'monarch-hook', '#!/bin/bash\nprintf \'["monarch-hook", ["post-update"]]\\n\' >> "$EVENTS"\nexec "' + str(tools / 'real-hook') + '" "$@"\n')
  hooks = home / '.config/monarch/hooks'
  (hooks / 'post-update.d').mkdir(parents=True)
  hook_probe = '''[[ -z ${MONARCH_UPDATE_SUDO_SESSION:-} && ! -e $SUDO_STATE ]] || touch "$HOOK_ESCALATED"
for pid in $(cat "$KEEPALIVE_PIDS"); do
  [[ ! -e /proc/$pid ]] || touch "$HOOK_ESCALATED"
done
if "''' + str(sudo) + '''" -n /usr/bin/true; then touch "$HOOK_ESCALATED"; fi
if sudo -n /usr/bin/true; then touch "$HOOK_ESCALATED"; fi
sudo /usr/bin/true
[[ ! -e $SUDO_STATE ]] || touch "$HOOK_ESCALATED"
echo hook >> "$HOOK_RUNS"
'''
  (hooks / 'post-update').write_text(hook_probe)
  (hooks / 'post-update.d/01-probe').write_text(hook_probe + '\nif [[ ${HOOK_REAUTHORIZE:-0} == 1 ]]; then "' + str(sudo) + '" /usr/bin/true; fi\n')
  (hooks / 'post-update.d/02-skip.sample').write_text('touch "$HOOK_ESCALATED"\n')
  executable(tools / 'monarch-restart-a-example', '#!/bin/bash\nsudo /usr/bin/true\necho service >> "$RESTART_RUNS"\nif [[ ${RESTART_REAUTHORIZE:-0} == 1 ]]; then "' + str(sudo) + '" /usr/bin/true; fi\n[[ ${FAIL_RESTART_REVOKE:-0} != 1 ]] || touch "$FAIL_REVOKE"\nexit "${RESTART_EXIT:-0}"\n')
  executable(tools / 'monarch-restart-pwn', '#!/bin/bash\n' + hook_probe.replace('echo hook >> "$HOOK_RUNS"', 'echo restart >> "$RESTART_RUNS"'))
  executable(tools / 'monarch-update-analyze-logs', (root / 'bin/monarch-update-analyze-logs').read_text().replace(
    'update_log="/tmp/monarch-update.log"', 'update_log="$UPDATE_LOG"\n[[ -z ${MONARCH_UPDATE_SUDO_SESSION:-} && ! -e $SUDO_STATE ]] || exit 18'))
  executable(tools / 'pacman', '#!/bin/bash\nexit 0\n')
  executable(tools / 'monarch-pkg-present', '#!/bin/bash\nexit 0\n')
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
if os.environ.get('AUR_INITRAMFS_FAILURE'):
  Path(os.environ['UPDATE_LOG']).write_text('Updating linux initcpios\\n')
sys.exit(int(os.environ.get('YAY_EXIT', '0')))
''')
  env = {key: value for key, value in os.environ.items() if key not in ('BASH_ENV', 'ENV', 'MONARCH_UPDATE_LOCKED', 'MONARCH_UPDATE_SUDO_SESSION', 'MONARCH_SUDO_NO_UPDATE')}
  user_bin = fixture / 'user-bin'
  user_bin.mkdir()
  for name in ('monarch-update-pkg-prune', 'monarch-snapshot', 'monarch-update-keyring', 'monarch-update-system-pkgs', 'monarch-reconcile', 'monarch-update-orphan-pkgs', 'monarch-pkg-present', 'sudo'):
    executable(user_bin / name, '#!/bin/bash\n"' + str(sudo) + '" -n /usr/bin/true && touch "$HELPER_POISON"\nexec "' + str(tools / name) + '" "$@"\n')
  env.update(HOME=str(home), MONARCH_PATH=str(trusted_root), MONARCH_RUNTIME_ROOT=str(trusted_root), MONARCH_UPDATE_LOGGED='1', XDG_RUNTIME_DIR=str(runtime),
    PATH=str(tools) + ':' + str(root / 'bin') + ':' + os.environ['PATH'], SUDO_STATE=str(fixture / 'sudo-state'),
    EVENTS=str(fixture / 'events'), ENTERED=str(fixture / 'entered'), FAIL_REVOKE=str(fixture / 'fail-revoke'), KEEPALIVE_PIDS=str(fixture / 'keepalive-pids'), UPDATE_LOG=str(fixture / 'update.log'), HOOK_ESCALATED=str(fixture / 'hook-escalated'), HOOK_RUNS=str(fixture / 'hook-runs'), RESTART_RUNS=str(fixture / 'restart-runs'), REAL_RESTART=str(restart), SLEEP_POISON=str(fixture / 'sleep-poison'), HELPER_POISON=str(fixture / 'helper-poison'))

  def run(extra=None, args=None, entry=None):
    (fixture / 'update.log').write_text('')
    for name in ('sudo-state', 'events', 'entered', 'fail-revoke', 'keepalive-pids', 'hook-escalated', 'hook-runs', 'restart-runs', 'sleep-poison', 'helper-poison'):
      (fixture / name).unlink(missing_ok=True)
    for marker in ('restart-a-example-required', 'restart-pwn-required'):
      (state / marker).touch()
    result = subprocess.run([str(entry or tools / 'monarch-update'), '-y', *(args or [])], env={**env, **(extra or {})}, capture_output=True, text=True, timeout=15)
    events = [json.loads(line) for line in (fixture / 'events').read_text().splitlines()] if (fixture / 'events').exists() else []
    assert not (fixture / 'hook-escalated').exists(), 'a user hook or dynamic restart inherited authorization'
    if not ((extra or {}).get('BREAK_REVOKE') or (extra or {}).get('FAIL_RESTART_REVOKE')):
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
  assert sum(event[0] == 'sudo' and event[2] == ['-N', '/usr/bin/true'] for event in events) == 6
  print('ok - long updates share one authorization and AUR sudo calls never refresh it')
  result, events = run({'PATH': str(user_bin) + ':' + env['PATH']})
  assert result.returncode == 0, result
  assert not (fixture / 'helper-poison').exists(), 'a PATH helper reused update authorization'
  result, events = run({'MONARCH_PATH': str(user_bin), 'MONARCH_RUNTIME_ROOT': str(user_bin), 'MONARCH_PACCACHE_BIN': str(user_bin / 'sudo')})
  assert result.returncode == 0, result
  assert not (fixture / 'helper-poison').exists(), 'a PATH or runtime override reused update authorization'
  print('ok - direct and transitive helpers ignore caller PATH and executable/runtime overrides')
  work_config = home / 'Work/.mise.toml'
  work_config.parent.mkdir()
  python_poison = fixture / 'python-poison'
  python_poison.mkdir()
  (python_poison / 'sitecustomize.py').write_text('import os, sys\nfrom pathlib import Path\nif sys.argv[0].endswith("mise-work-path.py"):\n  Path(os.environ["HELPER_POISON"]).touch()\n')
  user_site = home / '.local/lib' / ('python' + str(sys.version_info.major) + '.' + str(sys.version_info.minor)) / 'site-packages'
  user_site.mkdir(parents=True)
  shutil.copy2(python_poison / 'sitecustomize.py', user_site / 'sitecustomize.py')
  for extra in ({}, {'PYTHONPATH': str(python_poison)}):
    work_config.write_text('[env]\n_.path = "{{ cwd }}/bin"\nCUSTOM = "kept"\n')
    result, events = run({'RECONCILE_PYTHON': '1', **extra})
    assert result.returncode == 0, result
    assert not (fixture / 'helper-poison').exists(), 'Python loaded user code during update authorization'
    assert 'CUSTOM = "kept"' in work_config.read_text() and '_.path = []' in work_config.read_text()
  print('ok - real mise reconciliation ignores PYTHONPATH and user site modules while preserving custom settings')
  source = fixture / 'source'
  source.mkdir()
  git_env = {**env, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
  def git(*args):
    subprocess.run(['/usr/bin/git', '-C', str(source), *args], env=git_env, check=True, capture_output=True)
  git('init', '-b', 'main')
  git('config', 'user.name', 'Update fixture')
  git('config', 'user.email', 'fixture@example.invalid')
  (source / 'tracked').write_text('source\n')
  git('add', 'tracked')
  git('commit', '-m', 'fixture')
  git('branch', 'dev')
  remote = fixture / 'source-remote'
  subprocess.run(['/usr/bin/git', 'init', '--bare', str(remote)], env=git_env, check=True, capture_output=True)
  git('remote', 'add', 'origin', str(remote))
  git('push', '-u', 'origin', 'main', 'dev')
  source_probe = '#!/bin/bash\n[[ ! -e $SUDO_STATE && -z ${MONARCH_UPDATE_SUDO_SESSION:-} ]] || touch "$HELPER_POISON"\n"' + str(sudo) + '" -n /usr/bin/true && touch "$HELPER_POISON"\necho source >> "' + str(fixture / 'source-hooks') + '"\n'
  executable(source / '.git/hooks/post-checkout', source_probe)
  executable(user_bin / 'git', source_probe + 'exec /usr/bin/git "$@"\n')
  executable(tools / 'monarch-update-time', '#!/bin/bash\n[[ ${MONARCH_UPDATE_SUDO_SESSION:-0} == 1 ]] || exit 19\n')
  executable(tools / 'niri', '#!/bin/bash\nexit 0\n')
  shutil.copy2(root / 'bin/monarch-update-git', tools / 'monarch-update-git')
  shutil.copy2(root / 'bin/monarch-update-switch-branch', tools / 'monarch-update-switch-branch')
  for checkout, branch in ((source, 'dev'), (fixture / 'source-worktree', 'main')):
    if checkout != source:
      git('worktree', 'add', str(checkout), branch)
    (checkout / 'bin').mkdir()
    source_entry = checkout / 'bin/monarch-update'
    executable(source_entry, (tools / 'monarch-update').read_text().replace('runtime_root=' + str(fixture / 'missing-packaged-runtime'), 'runtime_root=' + str(trusted_root)))
    result, events = run({'PATH': str(user_bin) + ':' + env['PATH'], 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}, ['--branch', branch], source_entry)
    assert result.returncode == 0, result
    assert not (fixture / 'helper-poison').exists(), 'source Git inherited system authorization'
    selected = subprocess.check_output(['/usr/bin/git', '-C', str(checkout), 'branch', '--show-current'], env=git_env, text=True).strip()
    assert selected == branch, selected
    assert sum(event[0] == 'sudo' and event[2] == ['/usr/bin/true'] for event in events) == 1
  assert (fixture / 'source-hooks').exists(), 'source hooks did not exercise the cold authorization boundary'
  executable(tools / 'monarch-update-git', script)
  print('ok - source checkout and worktree updates switch and pull without sudo, then authenticate once in the packaged runtime')
  for extra in ({'UNTRUSTED_OWNER': '1'}, {'UNTRUSTED_PARENT': '1'}):
    result, events = run(extra)
    assert result.returncode != 0 and all(event[0] == 'sudo' and event[2] == ['-k'] for event in events), result
  for path in (trusted_root, tools / 'monarch-reconcile'):
    original_mode = path.stat().st_mode & 0o777
    try:
      path.chmod(0o777)
      result, events = run()
      assert result.returncode != 0 and all(event[0] == 'sudo' and event[2] == ['-k'] for event in events), result
    finally:
      path.chmod(original_mode)
  print('ok - untrusted runtime owners, parents, directories and helper modes fail before authentication')
  (trusted_root / '.git').mkdir()
  try:
    result, events = run()
    assert result.returncode != 0 and all(event[0] == 'sudo' and event[2] == ['-k'] for event in events), result
  finally:
    (trusted_root / '.git').rmdir()
  unsafe_parent = fixture / 'unsafe-parent'
  unsafe_parent.mkdir()
  unsafe_parent.chmod(0o777)
  (unsafe_parent / 'payload').write_text('unsafe\n')
  (trusted_root / 'unsafe-link').symlink_to(unsafe_parent / 'payload')
  try:
    result, events = run()
    assert result.returncode != 0 and all(event[0] == 'sudo' and event[2] == ['-k'] for event in events), result
  finally:
    (trusted_root / 'unsafe-link').unlink()
  print('ok - source checkouts without a trusted package and symlinks through writable parents fail before authentication')
  result, events = run({'POISON_PATH_SLEEP': '1'})
  assert result.returncode == 0, result
  assert not (fixture / 'sleep-poison').exists(), 'PATH sleep reused update authorization'
  for name in ('sleep', 'wait', 'kill'):
    delegate = '"' + str(trusted_sleep) + '"' if name == 'sleep' else 'builtin ' + name
    function = '() { if [[ ${MONARCH_UPDATE_SUDO_SESSION:-0} == 1 ]]; then "' + str(sudo) + '" -n /usr/bin/true && touch "$SLEEP_POISON"; fi; ' + delegate + ' "$@"; }'
    result, events = run({'BASH_FUNC_' + name + '%%': function})
    assert result.returncode == 0, result
    assert not (fixture / 'sleep-poison').exists(), ('imported function reused authorization', name)
  print('ok - keepalive ignores PATH sleep and imported sleep/wait/kill functions')
  (fixture / 'updater-bash-env').write_text('touch "$SLEEP_POISON"\n')
  result, events = run({'BASH_ENV': str(fixture / 'updater-bash-env'), 'ENV': str(fixture / 'updater-bash-env'), 'SHELLOPTS': 'noexec', 'BASHOPTS': 'extdebug', 'CDPATH': str(fixture), 'GLOBIGNORE': '*'})
  assert result.returncode == 0, result
  assert not (fixture / 'sleep-poison').exists(), 'an updater startup hook executed'
  print('ok - updater and its children ignore inherited Bash startup hooks and options')
  assert (fixture / 'hook-runs').read_text() == 'hook\nhook\n'
  assert (fixture / 'restart-runs').read_text() == 'service\nrestart\n'
  result, events = run({'RESTART_REAUTHORIZE': '1'})
  assert result.returncode == 0, result
  assert (fixture / 'restart-runs').read_text() == 'service\nrestart\n'
  print('ok - marker-driven restarts cannot inherit update or previous restart credentials')
  result, events = run({'RESTART_EXIT': '29', 'RESTART_REAUTHORIZE': '1'})
  assert result.returncode == 29, result
  assert (state / 'restart-a-example-required').exists()
  assert (fixture / 'restart-runs').read_text() == 'service\n'
  assert not any(event[0] in ('monarch-hook', 'yay') for event in events)
  result, events = run({'FAIL_RESTART_REVOKE': '1', 'RESTART_REAUTHORIZE': '1'})
  assert result.returncode != 0, result
  assert (fixture / 'restart-runs').read_text() == 'service\n'
  assert (state / 'restart-a-example-required').exists()
  assert not any(event[0] in ('monarch-hook', 'yay') for event in events)
  print('ok - restart or revocation failures preserve pending markers and stop subsequent user code')
  result, events = run({'HOOK_REAUTHORIZE': '1'})
  assert result.returncode == 0, result
  assert (fixture / 'hook-runs').read_text() == 'hook\nhook\n'
  print('ok - both user hook slots run after revocation and fresh hook credentials are revoked before AUR')
  result, events = run({'AUR_INITRAMFS_FAILURE': '1'})
  assert result.returncode == 0, result
  warning = 'Initramfs generation may have failed'
  assert warning in result.stdout, result.stdout
  assert result.stdout.index(warning) < result.stdout.index('reboot check'), result.stdout
  print('ok - AUR initramfs failures are reported without authorization before reboot checks')
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
  assert not any(event[0] == 'monarch-hook' for event in events)
  print('ok - failed revocation prevents user hooks and AUR execution')
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
  startup_env = {**env, 'BASH_ENV': str(fixture / 'bash-env'),
    'BASH_FUNC_exec%%': '() { touch ' + str(poison) + '; }'}
  subprocess.run([str(wrapper), '/usr/bin/true'], env=startup_env, check=True)
  assert not poison.exists()
  unsafe = subprocess.run(['bash', str(wrapper), '/usr/bin/true'], env=startup_env, capture_output=True)
  assert unsafe.returncode == 126
  assert poison.exists(), 'BASH_ENV must demonstrate execution before the in-script guard'
  print('ok - the no-update sudo wrapper suppresses startup hooks and imported functions before its guard')
  modules = fixture / 'modules/running'
  modules.mkdir(parents=True)
  (modules / 'vmlinuz').touch()
  executable(tools / 'uname', '#!/bin/bash\necho running\n')
  executable(tools / 'gum', '#!/bin/bash\necho prompt >> "$RESTART_LOG"\nexit "${GUM_STATUS:-1}"\n')
  executable(tools / 'monarch-system-reboot', '#!/bin/bash\necho reboot >> "$RESTART_LOG"\nexit "${REBOOT_STATUS:-0}"\n')
  executable(tools / 'monarch-restart-example', '#!/bin/bash\necho service >> "$RESTART_LOG"\n')
  executable(tools / 'monarch-state', '#!/bin/bash\nrm -f "$HOME/.local/state/monarch/$2"\n')
  for marker in ('restart-a-example-required', 'restart-pwn-required'):
    (state / marker).unlink(missing_ok=True)
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
  for status in (27, 0):
    restart_log.write_text('')
    result = subprocess.run([str(restart), '--reboot-only'], env={**restart_env, 'MONARCH_UPDATE_UNATTENDED': '0', 'GUM_STATUS': '0', 'REBOOT_STATUS': str(status)}, capture_output=True)
    assert result.returncode == status, result
    assert restart_log.read_text() == 'prompt\nreboot\n'
  print('ok - confirmed reboot scheduling preserves both failure and success status')
PY
