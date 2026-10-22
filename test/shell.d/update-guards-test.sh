#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
python3 - "$ROOT" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as temporary:
  root = Path(temporary)
  runtime = root / 'runtime'
  runtime.mkdir(mode=0o700)
  tools = root / 'bin'
  tools.mkdir()
  source = repo / 'default/monarch/update-guards.py'
  helper = root / 'guards.py'
  helper.write_text(source.read_text().replace("'/usr/bin/setpriv'", repr(str(tools / 'setpriv')))
    .replace('time.monotonic() + 60', 'time.monotonic() + 0.5'))
  spec = importlib.util.spec_from_file_location('guards', helper)
  guards = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(guards)

  def script(name, body):
    path = tools / name
    path.write_text('#!/bin/bash\nset -e\n' + body)
    path.chmod(0o755)

  script('setpriv', 'shift 5; exec "$@"')
  script('pkexec', 'exec "$@"')
  script('systemd-inhibit', '''
echo "$$" >>"$LAUNCHES"
case ${LAUNCH_MODE:-ready} in
  fail) exit 42 ;;
  late) sleep 1 ;;
  never) exec sleep 60 ;;
esac
while [[ $1 == --* ]]; do shift; done
exec "$@"
''')
  script('monarch-toggle-idle', '''
case $1 in
  claim)
    [[ ${CAFFEINE_FAIL:-0} != 1 ]] || exit 1
    [[ ! -f $CAFFEINE ]] || exit 1
    printf '%s\\n' "$2" >"$CAFFEINE" ;;
  release)
    [[ ${RELEASE_FAIL:-0} != 1 ]] || exit 1
    [[ ! -f $CAFFEINE || $(cat "$CAFFEINE") != "$2" ]] || rm "$CAFFEINE" ;;
esac
''')
  launches = root / 'launches'
  caffeine = root / 'caffeine'
  env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), PATH=str(tools)+':/usr/bin:/bin',
    LAUNCHES=str(launches), CAFFEINE=str(caffeine))
  env.pop('MONARCH_UPDATE_SUDO_SESSION', None)
  state = runtime / 'monarch-update-stay-awake'

  def run(action, *args, changes=None, expected=0):
    result = subprocess.run(['/usr/bin/python3', '-I', str(helper), action, *args],
      env=dict(env, **(changes or {})), capture_output=True, text=True, timeout=5)
    assert result.returncode == expected, (action, result.returncode, result.stdout, result.stderr)
    return result

  def wait_dead(pid):
    for _ in range(100):
      try:
        if guards.process(pid)[0] == 'Z':
          return
      except FileNotFoundError:
        return
      time.sleep(0.02)
    raise AssertionError(f'process survived: {pid}')

  run('held', changes={'MONARCH_UPDATE_LOCKED': '1'}, expected=1)
  run('run', '/bin/bash', '-c', f'/usr/bin/python3 -I {helper} held')
  run('run', '/bin/bash', '-c', 'exit 42', expected=42)
  run('run', '/bin/bash', '-c', f'''exec 9>"$XDG_RUNTIME_DIR/monarch-update.lock"
export MONARCH_UPDATE_LOCK_PID=$$ MONARCH_UPDATE_LOCK_OWNER_FD=9
/usr/bin/python3 -I {helper} held''', expected=1)
  print('PASS: forged environment cannot prove a lock; actual descendants can; exit status survives')

  sleeper = subprocess.Popen(['sleep', '60'])
  try:
    run('held', changes={'MONARCH_UPDATE_LOCK_PID': str(sleeper.pid),
      'MONARCH_UPDATE_LOCK_OWNER_FD': '0'}, expected=1)
  finally:
    sleeper.terminate()
    sleeper.wait()
  marker = root / 'locked'
  owner = subprocess.Popen(['/usr/bin/python3', '-I', str(helper), 'run', '/bin/bash', '-c',
    f'touch {marker}; sleep 0.5'], env=env)
  while not marker.exists():
    time.sleep(0.01)
  owner_fd = next(p.name for p in Path(f'/proc/{owner.pid}/fd').iterdir()
    if p.resolve() == runtime / 'monarch-update.lock')
  run('held', changes={'MONARCH_UPDATE_LOCK_PID': str(owner.pid),
    'MONARCH_UPDATE_LOCK_OWNER_FD': owner_fd}, expected=1)
  run('run', 'true', changes={'MONARCH_UPDATE_LOCKED': '1'}, expected=1)
  owner.wait(timeout=3)
  run('run', 'true')
  lock = runtime / 'monarch-update.lock'
  lock.unlink()
  sentinel = root / 'sentinel'
  sentinel.write_text('untouched')
  lock.symlink_to(sentinel)
  run('run', 'true', expected=1)
  assert sentinel.read_text() == 'untouched'
  lock.unlink()
  print('PASS: concurrent lock cannot be bypassed and lock symlinks are refused without writes')

  for mode in ('fail', 'never', 'late'):
    run('start', changes={'LAUNCH_MODE': mode}, expected=1)
    assert not state.exists() and not caffeine.exists()
    pid = int(launches.read_text().splitlines()[-1])
    wait_dead(pid)
  time.sleep(0.7)
  assert not state.exists()
  print('PASS: failures, absent readiness and delayed launches roll back without resurrecting state')

  run('start')
  record = json.loads((state / 'inhibit-pid').read_text())
  assert guards.identity_matches(record)
  assert state.stat().st_mode & 0o777 == 0o700
  assert all(p.stat().st_mode & 0o777 == 0o600 for p in state.iterdir())
  assert caffeine.read_text().strip() == 'update:' + record[2]
  run('stop')
  wait_dead(record[0])
  assert not state.exists() and not caffeine.exists()
  run('stop')
  print('PASS: readiness identifies the actual user-owned holder; private state and repeatable cleanup')

  caffeine.write_text('user\n')
  run('start')
  run('stop')
  assert caffeine.read_text() == 'user\n'
  caffeine.unlink()
  run('start')
  caffeine.write_text('new-user-choice\n')
  run('stop')
  assert caffeine.read_text() == 'new-user-choice\n'
  caffeine.unlink()
  run('start', changes={'CAFFEINE_FAIL': '1'})
  run('stop')
  run('start')
  run('stop', changes={'RELEASE_FAIL': '1'}, expected=1)
  assert (state / 'idle-owner').exists()
  run('stop')
  print('PASS: Caffeine preserves existing/new user choices and failed release remains retryable')

  victim = subprocess.Popen(['sleep', '60'])
  try:
    state.mkdir(mode=0o700)
    record = [victim.pid, guards.process(victim.pid)[2], 'a'*32]
    guards.publish(state / 'inhibit-pid', json.dumps(record))
    run('stop')
    assert victim.poll() is None
    state.mkdir(mode=0o700)
    (state / 'inhibit-pid').symlink_to(sentinel)
    run('stop', expected=1)
    assert sentinel.read_text() == 'untouched' and victim.poll() is None
    (state / 'inhibit-pid').unlink()
    state.rmdir()
    state.symlink_to(root)
    run('start', expected=1)
    state.unlink()
    runtime.chmod(0o777)
    run('start', expected=1)
    runtime.chmod(0o700)
  finally:
    victim.terminate()
    victim.wait()
  print('PASS: stale/forged identities never signal unrelated processes; unsafe state is refused')

  legacy = subprocess.Popen(['/usr/bin/python3', '-c', 'import time; time.sleep(60)',
    'systemd-inhibit', '--why=Monarch update in progress'])
  state.mkdir(mode=0o755)
  (state / 'inhibit-pid').write_text(f'{legacy.pid} {guards.process(legacy.pid)[2]}\n')
  run('stop')
  legacy.wait(timeout=3)
  assert not state.exists()
  print('PASS: cleanup accepts the verified legacy two-field record across a package upgrade')

  launches.write_text('')
  pending = subprocess.Popen(['/usr/bin/python3', '-I', str(helper), 'start'],
    env=dict(env, LAUNCH_MODE='late'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
  while not launches.read_text():
    time.sleep(0.01)
  pending.send_signal(signal.SIGTERM)
  assert pending.wait(timeout=5) == 143
  time.sleep(1.1)
  assert not state.exists() and not caffeine.exists()
  print('PASS: TERM during acquisition cancels publication and cleans pending state')
PY
