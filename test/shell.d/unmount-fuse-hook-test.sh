#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
source = (root / 'default/systemd/system-sleep/unmount-fuse').read_text()
assert source.splitlines()[0] == '#!/bin/bash -p'
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    users = tmp / 'users'
    users.mkdir()
    calls = tmp / 'calls'
    mounts = tmp / 'mounts'
    mounts.write_text('')
    sockets = []
    metadata = {}
    metadata_file = tmp / 'metadata'
    fail_file = tmp / 'fail'
    mocks = tmp / 'bin'
    mocks.mkdir()
    recorder = f'''#!/usr/bin/python3
import json, os, signal, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
with open({str(calls)!r}, 'a') as log:
    log.write(json.dumps([name, sys.argv[1:], dict(os.environ)]) + '\\n')
if name == 'stat':
    data = json.loads(Path({str(metadata_file)!r}).read_text())[sys.argv[-1]]
    print(data if sys.argv[2] == '%u:%a' else data.split(':')[0])
fail = Path({str(fail_file)!r})
if fail.exists() and ('hang-' + name) in fail.read_text().split():
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(30)
if fail.exists() and name in fail.read_text().split():
    print(name + ': simulated failure', file=sys.stderr)
    sys.exit(23)
'''
    for name in ('systemd-run', 'systemctl', 'fusermount3', 'fusermount', 'stat'):
        path = mocks / name
        path.write_text(recorder)
        path.chmod(0o755)
    hook = tmp / 'hook'
    transformed = source.replace('/run/user/', str(users) + '/')
    transformed = transformed.replace('/proc/mounts', str(mounts))
    for name in ('systemd-run', 'systemctl', 'fusermount3', 'fusermount', 'stat'):
        transformed = transformed.replace('/usr/bin/' + name, str(mocks / name))
    hook.write_text(transformed)
    hook.chmod(0o755)

    def session(uid, *, bus=True, owner=None, mode='700', bus_owner=None):
        directory = users / str(uid)
        directory.mkdir()
        metadata[str(directory)] = f'{owner or uid}:{mode}'
        if bus:
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(directory / 'bus'))
            sockets.append(sock)
            metadata[str(directory / 'bus')] = f'{bus_owner or uid}:600'
        metadata_file.write_text(json.dumps(metadata))
        return directory

    def run(phase, *, fail='', args=None, env=None, code=0):
        calls.write_text('')
        fail_file.write_text(fail)
        result = subprocess.run(args or [str(hook), phase, 'suspend'],
                                capture_output=True, text=True, timeout=3,
                                env=env)
        assert result.returncode == code, (result.returncode, result.stderr)
        records = [json.loads(line) for line in calls.read_text().splitlines()]
        return result, records

    def scheduled(records):
        return [args for name, args, _ in records if name == 'systemd-run']

    result, records = run('post')
    assert not records
    print('PASS: no sessions means no timer and no restart')
    session(1000)
    session(1001)
    session(1002, bus=False)
    env = dict(os.environ, PATH=str(mocks), XDG_RUNTIME_DIR='/hostile',
               DBUS_SESSION_BUS_ADDRESS='unix:path=/hostile', LD_PRELOAD='',
               SECRET='not-for-the-service')
    result, records = run('post', env=env)
    jobs = scheduled(records)
    assert len(jobs) == 2
    expected_prefix = ['--quiet', '--no-block', '--collect', '--on-active=5',
                       '--timer-property=AccuracySec=1s']
    for uid, args in zip((1000, 1001), jobs):
        directory = users / str(uid)
        assert args == expected_prefix + [f'--uid={uid}', '--property=Type=exec',
            '--property=NoNewPrivileges=yes', '--property=RuntimeMaxSec=30s',
            '--property=TimeoutStartSec=30s', '/usr/bin/env', '-i',
            'PATH=/usr/bin:/bin', f'DBUS_SESSION_BUS_ADDRESS=unix:path={directory}/bus',
            f'XDG_RUNTIME_DIR={directory}', str(mocks / 'systemctl'),
            '--user', 'restart', 'gvfs-daemon.service'], args
        assert not any(name == 'systemctl' for name, _, _ in records)
        command = args[args.index('/usr/bin/env'):]
        completed = subprocess.run(command, capture_output=True, timeout=3)
        assert completed.returncode == 0
    services = [r for r in map(json.loads, calls.read_text().splitlines()) if r[0] == 'systemctl']
    assert len(services) == 2
    for _, args, service_env in services:
        assert args == ['--user', 'restart', 'gvfs-daemon.service']
        assert service_env['PATH'] == '/usr/bin:/bin'
        assert 'SECRET' not in service_env and 'LD_PRELOAD' not in service_env
    print('PASS: multiple users, exact system timer arguments and clean service environments')

    fail_file.write_text('systemctl')
    completed = subprocess.run(command, capture_output=True, text=True, timeout=3)
    assert completed.returncode == 23 and 'simulated failure' in completed.stderr
    print('PASS: delayed restart failure remains nonzero with diagnostics for the service journal')

    result, records = run('post', fail='systemd-run', code=1)
    assert len(scheduled(records)) == 2
    assert 'simulated failure' in result.stderr and 'UID 1000' in result.stderr and 'UID 1001' in result.stderr
    print('PASS: submission failures are diagnosed without skipping other users')

    hook.write_text(transformed.replace('--kill-after=1s 10s', '--kill-after=0.1s 0.2s'))
    result, records = run('post', fail='hang-systemd-run', code=1)
    assert len(scheduled(records)) == 2 and result.stderr.count('could not schedule') == 2
    hook.write_text(transformed)
    print('PASS: blocked system-manager submissions have a handled deadline')

    for name in ('0', '01000', '-1', '4294967295', '99999999999', 'user;bad'):
        session(name)
    result, records = run('post')
    assert len(scheduled(records)) == 2
    assert result.stderr.count('invalid user runtime UID') == 6
    print('PASS: root, noncanonical, overflowing and malformed UIDs cannot schedule jobs')

    session(1003, owner=1004)
    session(1004, mode='777')
    session(1005, bus_owner=1006)
    (users / '1006').symlink_to(users / '1000', target_is_directory=True)
    directory = session(1007, bus=False)
    (directory / 'bus').symlink_to(users / '1000/bus')
    directory = session(1008, bus=False)
    (directory / 'bus').write_text('not a socket')
    result, records = run('post', code=1)
    assert len(scheduled(records)) == 2
    assert result.stderr.count('unsafe runtime directory') == 3
    assert result.stderr.count('unsafe user bus') == 3
    print('PASS: runtime ownership, permissions, symlinks and bus type/ownership are checked')

    mounts.write_text('gvfsd-fuse /run/user/1000/gvfs fuse.gvfsd-fuse rw 0 0\n'
                      'other /ignored fuse.other rw 0 0\n'
                      'gvfsd-fuse /with\\040space\\134slash fuse.gvfsd-fuse rw 0 0\n')
    result, records = run('pre')
    assert [(name, args) for name, args, _ in records] == [
        ('fusermount3', ['-uz', '/run/user/1000/gvfs']),
        ('fusermount3', ['-uz', '/with space\\slash'])]
    result, records = run('pre', fail='fusermount3')
    assert [r[0] for r in records] == ['fusermount3', 'fusermount'] * 2
    result, records = run('pre', fail='fusermount3 fusermount', code=1)
    assert len(records) == 4 and result.stderr.count('could not detach') == 2
    print('PASS: pre-unmount filtering, escaped paths, fallback and errors are preserved')

    injected = tmp / 'injected'
    bash_env = tmp / 'bash_env'
    bash_env.write_text(f'touch {injected}\n')
    env = dict(os.environ, BASH_ENV=str(bash_env))
    env['BASH_FUNC_printf%%'] = f'() {{ /usr/bin/touch {injected}; }}'
    result, records = run('pre', env=env)
    assert not injected.exists()
    result, records = run('post', args=['/bin/bash', str(hook), '-p', 'post'], code=1)
    assert 'privileged Bash is required' in result.stderr and not records
    result, records = run('unknown')
    assert not records
    print('PASS: direct shebang blocks startup injection and ordinary Bash with a decoy -p is rejected')

    # A background child holding stdout would prevent communicate() from finishing.
    result, records = run('post', code=1)
    assert len(scheduled(records)) == 2
    print('PASS: resume closes its pipes promptly; no background sleep or user-manager call')

    system_root = tmp / 'system-root'
    legacy_hook = system_root / 'usr/lib/systemd/system-sleep/unmount-fuse'
    legacy_hook.parent.mkdir(parents=True)
    legacy_hook.write_text('legacy')
    owned = tmp / 'owned'
    pacman = mocks / 'pacman'
    pacman.write_text(recorder + f'''
if sys.argv[1] == '-Qo':
    sys.exit(0 if Path({str(owned)!r}).exists() else 1)
''')
    pacman.chmod(0o755)
    sudo = mocks / 'sudo'
    sudo.write_text('#!/bin/bash\nexec "$@"\n')
    sudo.chmod(0o755)
    fail_file.write_text('')
    calls.write_text('')
    bootstrap = root / 'install/reconcile/packaged-runtime-bootstrap.sh'
    command = ['/bin/bash', '-c', 'source "$1"; monarch_install_packaged_runtime true',
               '_', str(bootstrap)]
    env = dict(os.environ, PATH=f'{mocks}:/usr/bin:/bin',
               MONARCH_LEGACY_SYSTEM_ROOT=str(system_root))
    completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3)
    assert completed.returncode == 0, completed.stderr
    records = [json.loads(line) for line in calls.read_text().splitlines()]
    assert [(name, args) for name, args, _ in records] == [
        ('pacman', ['-Qo', str(legacy_hook)]),
        ('pacman', ['-S', '--noconfirm', '--needed', '--overwrite',
                    'usr/lib/systemd/system-sleep/unmount-fuse', 'monarch'])]
    owned.touch()
    calls.write_text('')
    completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3)
    assert completed.returncode == 1 and 'package-owned legacy path' in completed.stderr
    records = [json.loads(line) for line in calls.read_text().splitlines()]
    assert len(records) == 1 and records[0][1][0] == '-Qo'
    print('PASS: existing bootstrap adopts only the unowned legacy hook and refuses foreign package ownership')
    for sock in sockets:
        sock.close()
PY
