#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as temporary:
  root = Path(temporary)
  runtime = root / 'runtime'
  tools = runtime / 'bin'
  tools.mkdir(parents=True)
  home = root / 'home'
  home.mkdir()
  events = root / 'events'
  cache = root / 'cache'
  for name in ('monarch-update', 'monarch-update-aur-pkgs', 'monarch-update-lock'):
    shutil.copy2(repo / 'bin' / name, tools / name)
  for relative in ('default/monarch/update-authorization.sh', 'default/monarch/sudo-no-update/sudo'):
    source = repo / relative
    if source.exists():
      target = runtime / relative
      target.parent.mkdir(parents=True, exist_ok=True)
      text = source.read_text()
      assert '/usr/bin/sudo' in text, relative
      if relative.endswith('update-authorization.sh'):
        assert text.count('/usr/bin/sleep 60') == 1
        text = text.replace('/usr/bin/sleep 60', '/usr/bin/sleep 0.05')
      target.write_text(text.replace('/usr/bin/sudo', str(tools / 'sudo')))
      target.chmod(source.stat().st_mode)

  def executable(name, text):
    target = tools / name
    target.write_text('#!/bin/bash\nset -e\n' + text)
    target.chmod(0o755)

  executable('sudo', r'''
printf 'sudo %s\n' "$*" >>"$EVENTS"
case "$*" in
  -h) [[ ${UNSUPPORTED:-0} != 1 ]] && echo 'usage: sudo [-Nn] command'; exit ;;
  -k)
    [[ ${FAIL_REVOKE:-0} != 1 ]] || exit 1
    [[ ${FAIL_FINAL_REVOKE:-0} != 1 || ! -e $AUTH_COMPLETED ]] || exit 1
    rm -f "$CACHE"; exit ;;
esac
no_update=0
noninteractive=0
while [[ ${1:-} == -* ]]; do
  case "$1" in
    -N) no_update=1 ;;
    -n) noninteractive=1 ;;
    --) shift; break ;;
    *) exit 98 ;;
  esac
  shift
done
[[ $* == /usr/bin/true ]] || exit 97
[[ ${FAIL_AUTH:-0} != 1 ]] || exit 1
(( ! noninteractive )) || [[ -e $CACHE ]] || exit 1
(( ! noninteractive )) || printf 'renewed\n' >>"$RENEWALS"
(( no_update )) || touch "$CACHE"
(( no_update || noninteractive )) || touch "$AUTH_COMPLETED"
''')
  executable('step', r'''
name=${0##*/}
warm=no
[[ ! -e $CACHE ]] || warm=yes
printf 'step %s warm=%s args=%s\n' "$name" "$warm" "$*" >>"$EVENTS"
[[ ${FAIL_STEP:-} != "$name" ]] || exit 42
if [[ ${SIGNAL_STEP:-} == "$name" ]]; then kill -TERM "$PPID"; exit 0; fi
[[ ${HOLD_STEP:-} != "$name" ]] || sleep 0.2
case "$name" in
  monarch-update-available)
    if [[ ${REPAIR:-0} == 1 && ! -e $KEYRING_READY ]]; then
      echo '{"status":"error","count":null,"reason":"repositories-unavailable"}'; exit 2
    fi
    if [[ ${CURRENT:-0} == 1 ]]; then echo '{"status":"current","count":0}'; exit 1; fi
    echo '{"status":"available","count":2}' ;;
  monarch-update-keyring) touch "$KEYRING_READY" ;;
  monarch-hook)
    [[ ${USER_TOOL_REQUIRED:-0} != 1 ]] || user-update-tool ;;
  monarch-update-confirm | gum) exit "${CANCEL:-0}" ;;
  pacman) echo 'example 1' ;;
  yay)
    sleep 0.1
    [[ ! -e $CACHE ]] || { echo 'AUR inherited cached sudo' >&2; exit 89; }
    [[ $* == *--sudoloop=false* ]] || exit 88
    sudo /usr/bin/true
    [[ ! -e $CACHE ]] || exit 87
    [[ $1 == --sudo ]] || exit 86
    "$2" /usr/bin/true
    [[ ! -e $CACHE ]] || exit 85 ;;
esac
''')
  steps = ('monarch-update-requires-free-space', 'monarch-update-pkg-prune',
    'monarch-snapshot', 'monarch-update-switch-branch', 'monarch-update-stay-awake',
    'monarch-update-git', 'monarch-update-keyring', 'monarch-update-system-pkgs',
    'monarch-reconcile', 'monarch-update-orphan-pkgs', 'monarch-hook',
    'monarch-update-analyze-logs', 'monarch-update-restart', 'monarch-update-available',
    'monarch-update-confirm', 'monarch-pkg-aur-accessible', 'pacman', 'yay', 'gum')
  for name in steps:
    (tools / name).symlink_to('step')
  i18n = root / 'i18n'
  i18n.write_text('monarch_i18n_load() { :; }\nmonarch_message() { :; }\nmonarch_t() { echo "$1"; }\n')
  executable('monarch-i18n', f"printf '%s\\n' '{i18n}'\n")
  executable('script', '[[ $1 == -qefc ]] || exit 99\nexec /bin/bash -p -c "$2"\n')
  env = dict(os.environ, HOME=str(home), MONARCH_PATH=str(runtime),
    XDG_RUNTIME_DIR=str(root), MONARCH_UPDATE_LOGGED='1', PATH=str(tools)+':/usr/bin:/bin',
    EVENTS=str(events), CACHE=str(cache), KEYRING_READY=str(root / 'keyring-ready'),
    AUTH_COMPLETED=str(root / 'authorized'), RENEWALS=str(root / 'renewals'))
  for name in ('BASH_ENV', 'ENV', 'MONARCH_UPDATE_LOCKED', 'MONARCH_UPDATE_SUDO_SESSION',
      'MONARCH_UPDATE_SUDO_NO_UPDATE', 'MONARCH_UPDATE_USER_PATH'):
    env.pop(name, None)

  def run(*args, changes=None, success=True):
    events.write_text('')
    cache.touch()
    (root / 'keyring-ready').unlink(missing_ok=True)
    (root / 'authorized').unlink(missing_ok=True)
    (root / 'renewals').unlink(missing_ok=True)
    selected = dict(env, **(changes or {}))
    result = subprocess.run([str(tools / 'monarch-update'), *args], env=selected,
      capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) == success, (result.returncode, result.stdout,
      result.stderr, events.read_text())
    assert not cache.exists(), ('cached authorization survived', events.read_text())
    return events.read_text().splitlines(), result

  for logged in ('1', ''):
    lines, _ = run('-y', changes={'MONARCH_UPDATE_LOGGED': logged})
    aur = next(i for i, line in enumerate(lines) if line.startswith('step yay '))
    for name in ('monarch-update-system-pkgs', 'monarch-reconcile', 'monarch-hook',
        'monarch-update-orphan-pkgs'):
      position = next(i for i, line in enumerate(lines) if line.startswith('step '+name+' '))
      assert position < aur and 'warm=yes' in lines[position], lines
    assert lines[0] == 'sudo -k', lines
    services = next(i for i, line in enumerate(lines) if line.startswith('step monarch-update-restart ') and 'args=--services-only' in line)
    reboot = next(i for i, line in enumerate(lines) if line.startswith('step monarch-update-restart ') and 'args=--reboot-only' in line)
    assert services < aur < reboot and 'warm=yes' in lines[services] and 'warm=no' in lines[reboot], lines
    assert 'sudo -k' in lines[:aur], lines
    assert not any(line.startswith('sudo ') and line not in ('sudo -k', 'sudo -h')
      and not line.startswith('sudo -N ') for line in lines[aur:]), lines
  print('PASS: trusted stages precede cold AUR; direct and PTY launches finish cold')

  user_bin = root / 'user commands'
  user_bin.mkdir()
  for name in ('monarch-reconcile', 'monarch-update-system-pkgs'):
    path = user_bin / name
    path.write_text('#!/bin/bash\nexit 91\n')
    path.chmod(0o755)
  tool = user_bin / 'user-update-tool'
  tool.write_text('#!/bin/bash\nprintf "user-tool\\n" >>"$EVENTS"\n')
  tool.chmod(0o755)
  for logged in ('1', ''):
    lines, _ = run('-y', changes={'PATH': str(user_bin)+':'+env['PATH'],
      'USER_TOOL_REQUIRED': '1', 'MONARCH_UPDATE_LOGGED': logged})
    assert 'user-tool' in lines, lines
  print('PASS: packaged stages ignore user PATH overrides while hooks retain user tools')

  run('-y', changes={'HOLD_STEP': 'monarch-hook'})
  assert (root / 'renewals').read_text().count('renewed') >= 2
  print('PASS: long trusted steps renew authorization; the keepalive stops before AUR')

  for name in ('monarch-update-system-pkgs', 'monarch-reconcile', 'monarch-hook',
      'monarch-update-keyring', 'yay'):
    _, result = run('-y', changes={'FAIL_STEP': name}, success=False)
    assert result.returncode == 42, result
  _, result = run('-y', changes={'SIGNAL_STEP': 'monarch-hook'}, success=False)
  assert result.returncode == 143, result
  print('PASS: failures and TERM revoke authorization and preserve exit status')

  for changes in ({'CURRENT': '1'}, {'REPAIR': '1'}, {'CURRENT': '1', 'REPAIR': '1'}):
    run('-y', changes=changes)
  run(changes={'CANCEL': '1'}, success=False)
  for changes in ({'FAIL_AUTH': '1'}, {'UNSUPPORTED': '1'}):
    lines, _ = run('-y', changes=changes, success=False)
    assert not any('step monarch-update-system-pkgs ' in line for line in lines), lines
  print('PASS: current-package retries, keyring repair, cancellation and authorization failure stay cold')

  startup = root / 'startup'
  marker = root / 'startup-ran'
  startup.write_text(f'touch "{marker}"\n')
  run('-y', changes={'BASH_ENV': str(startup), 'ENV': str(startup),
    'BASH_FUNC_printf%%': f'() {{ /usr/bin/touch "{marker}"; }}'})
  assert not marker.exists(), 'startup code reached an update interpreter'
  for path in (tools / 'monarch-update', runtime / 'default/monarch/sudo-no-update/sudo'):
    events.write_text('')
    result = subprocess.run(['/bin/bash', str(path), '-p'], env=env,
      capture_output=True, text=True, timeout=10)
    assert result.returncode == 126 and not events.read_text(), result
  print('PASS: inherited startup files/functions and ordinary Bash cannot reach the sudo boundary')

  for change in ('FAIL_REVOKE', 'FAIL_FINAL_REVOKE'):
    events.write_text('')
    cache.touch()
    (root / 'authorized').unlink(missing_ok=True)
    result = subprocess.run([str(tools / 'monarch-update'), '-y'],
      env=dict(env, **{change: '1'}), capture_output=True, text=True, timeout=10)
    assert result.returncode != 0
    assert 'step yay ' not in events.read_text()
    assert ('step monarch-hook ' in events.read_text()) == (change == 'FAIL_FINAL_REVOKE')
  print('PASS: failed revocation prevents entry into AUR')

  events.write_text('')
  cache.touch()
  result = subprocess.run([str(tools / 'monarch-update-aur-pkgs')], env=env,
    capture_output=True, text=True, timeout=10)
  assert result.returncode == 0 and not cache.exists(), (result, events.read_text())
  assert 'step yay warm=no' in events.read_text()
  wrapper = runtime / 'default/monarch/sudo-no-update/sudo'
  for arguments in (['-v'], ['-n', '--', '/usr/bin/true'],
      ['--user', 'root', '--', '/usr/bin/true'], ['-k'], ['-K'], ['--help']):
    events.write_text('')
    subprocess.run([str(wrapper), *arguments], env=env, capture_output=True, timeout=5)
    expected = arguments if len(arguments) == 1 and arguments[0] in ('-k', '-K', '--help') else ['-N', *arguments]
    assert events.read_text().splitlines()[0] == 'sudo ' + ' '.join(expected)
  print('PASS: standalone AUR starts cold and the sudo wrapper preserves argument boundaries')

  lines, _ = run('-y', changes={'MONARCH_PATH': str(home)}, success=False)
  assert not any(line.startswith('step ') for line in lines), lines
  for relative in ('bin/monarch-update', 'bin/monarch-update-aur-pkgs'):
    link = root / ('installed-' + Path(relative).name)
    link.symlink_to(runtime / relative)
    cache.touch()
    result = subprocess.run([str(link), *(['-y'] if relative.endswith('monarch-update') else [])],
      env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0 and not cache.exists(), result
  print('PASS: mismatched runtimes fail closed and installed command symlinks resolve correctly')
PY
