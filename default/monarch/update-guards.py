import fcntl
import json
import os
from pathlib import Path
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
import time


def private_directory(path, legacy=False):
  info = path.lstat()
  mode = stat.S_IMODE(info.st_mode)
  if (not stat.S_ISDIR(info.st_mode) or path.resolve() != path or
      info.st_uid != os.getuid() or (mode != 0o700 and not (legacy and not mode & 0o022))):
    raise RuntimeError(f'Unsafe update state directory: {path}')
  if mode != 0o700:
    path.chmod(0o700)
  return path


def state_base():
  configured = os.environ.get('XDG_RUNTIME_DIR')
  if configured:
    path = private_directory(Path(configured))
  else:
    path = Path(f'/tmp/monarch-{os.getuid()}')
    path.mkdir(mode=0o700, exist_ok=True)
    private_directory(path, legacy=True)
  for parent in path.parents:
    info = parent.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, os.getuid()) or
        (info.st_mode & 0o022 and not (info.st_uid == 0 and info.st_mode & stat.S_ISVTX))):
      raise RuntimeError(f'Unsafe update state ancestor: {parent}')
  return path


def open_state(path, create=False, legacy=False):
  flags = os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
  fd = os.open(path, flags | (os.O_CREAT if create else 0), 0o600)
  info = os.fstat(fd)
  mode = stat.S_IMODE(info.st_mode)
  if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
      info.st_nlink != 1 or (mode != 0o600 and not (legacy and not mode & 0o022))):
    os.close(fd)
    raise RuntimeError(f'Unsafe update state file: {path}')
  return os.fdopen(fd, 'r+')


def read_state(path, legacy=False):
  with open_state(path, legacy=legacy) as stream:
    data = stream.read(4097)
  if len(data) > 4096 or not data.endswith('\n') or data.count('\n') != 1:
    raise RuntimeError(f'Invalid update state record: {path}')
  return data.rstrip('\n')


def publish(path, record):
  if path.exists() or path.is_symlink():
    with open_state(path):
      pass
  fd, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
  try:
    with os.fdopen(fd, 'w') as stream:
      stream.write(record + '\n')
    os.replace(temporary, path)
  finally:
    Path(temporary).unlink(missing_ok=True)


def process(pid):
  data = Path(f'/proc/{pid}/stat').read_text().rsplit(') ', 1)[1].split()
  return data[0], int(data[1]), data[19]


def lock_held(path):
  try:
    owner = int(os.environ['MONARCH_UPDATE_LOCK_PID'])
    fd = int(os.environ['MONARCH_UPDATE_LOCK_OWNER_FD'])
    ancestor = os.getppid()
    while ancestor > 1 and ancestor != owner:
      ancestor = process(ancestor)[1]
    if ancestor != owner:
      return False
    target = Path(f'/proc/{owner}/fd/{fd}')
    if not os.path.samefile(target, path):
      return False
    info = Path(f'/proc/{owner}/fdinfo/{fd}').read_text()
    return any(line.split()[2:5] == ['FLOCK', 'ADVISORY', 'WRITE']
      for line in info.splitlines() if line.startswith('lock:'))
  except (KeyError, ValueError, OSError):
    return False


def run_locked(base, args):
  if not args:
    raise RuntimeError('Usage: monarch-update-lock run <command> [args...]')
  with open_state(base / 'monarch-update.lock', create=True, legacy=True) as stream:
    try:
      fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
      raise RuntimeError('A Monarch update is already running.') from None
    env = dict(os.environ, MONARCH_UPDATE_LOCK_PID=str(os.getpid()),
      MONARCH_UPDATE_LOCK_OWNER_FD=str(stream.fileno()))
    env.pop('MONARCH_UPDATE_LOCKED', None)
    env.pop('MONARCH_UPDATE_LOCK_FD', None)
    child = subprocess.Popen(args, env=env, close_fds=True)
    def forward(number, frame):
      child.send_signal(number)
    for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
      signal.signal(number, forward)
    status = child.wait()
    return status if status >= 0 else 128 - status


def identity_matches(record):
  pid, started, token = record
  try:
    state, _, actual_start = process(pid)
    args = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
    owner = Path(f'/proc/{pid}').stat().st_uid
    if token == '--why=Monarch update in progress':
      status = Path(f'/proc/{pid}/status').read_text().splitlines()
      owner = int(next(line for line in status if line.startswith('Uid:')).split()[1])
      if not any(Path(os.fsdecode(arg)).name == 'systemd-inhibit' for arg in args if arg):
        return False
    return (state != 'Z' and actual_start == started and token.encode() in args and
      owner == os.getuid())
  except (OSError, ValueError):
    return False


def terminate(record):
  pid, _, _ = record
  try:
    fd = os.pidfd_open(pid)
  except ProcessLookupError:
    return
  try:
    if not identity_matches(record):
      return
    signal.pidfd_send_signal(fd, signal.SIGTERM)
    for _ in range(100):
      if not identity_matches(record):
        return
      time.sleep(0.02)
    raise RuntimeError('Failed to stop the Monarch update sleep inhibitor.')
  finally:
    os.close(fd)


def inhibitor_record(directory):
  text = read_state(directory / 'inhibit-pid', legacy=True)
  legacy = text.split()
  if len(legacy) == 2 and all(part.isdigit() for part in legacy) and int(legacy[0]) > 1:
    return [int(legacy[0]), legacy[1], '--why=Monarch update in progress']
  record = json.loads(text)
  if (not isinstance(record, list) or len(record) != 3 or type(record[0]) is not int or
      record[0] <= 1 or not isinstance(record[1], str) or not record[1].isdigit() or
      not isinstance(record[2], str) or len(record[2]) != 32 or
      any(c not in '0123456789abcdef' for c in record[2])):
    raise RuntimeError('Invalid update inhibitor identity.')
  return record


def stop_inhibitor(directory):
  if not directory.exists() and not directory.is_symlink():
    return
  private_directory(directory, legacy=True)
  control = directory / 'launch-control'
  if control.exists() or control.is_symlink():
    with open_state(control) as stream:
      fcntl.flock(stream, fcntl.LOCK_EX)
      stream.seek(0)
      stream.truncate()
      stream.write('cancelled\n')
      stream.flush()
      control.unlink()
  record_path = directory / 'inhibit-pid'
  if record_path.exists() or record_path.is_symlink():
    record = inhibitor_record(directory)
    if record[2] == '--why=Monarch update in progress' and not identity_matches(record):
      try:
        state, _, started = process(record[0])
        if state != 'Z' and started == record[1]:
          raise RuntimeError('Cannot verify the legacy update inhibitor; retained its state.')
      except FileNotFoundError:
        pass
    terminate(record)
    record_path.unlink()
  owner_path = directory / 'idle-owner'
  if owner_path.exists() or owner_path.is_symlink():
    owner = read_state(owner_path, legacy=True)
    if not owner or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:._-' for c in owner):
      raise RuntimeError('Invalid update Caffeine ownership.')
    subprocess.run(['monarch-toggle-idle', 'release', owner], check=True)
    owner_path.unlink()
  directory.rmdir()


def hold(directory, token):
  private_directory(directory)
  signal.signal(signal.SIGTERM, lambda number, frame: sys.exit(0))
  signal.signal(signal.SIGHUP, lambda number, frame: sys.exit(0))
  with open_state(directory / 'launch-control') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX)
    if stream.read() != token + '\n':
      return 1
    publish(directory / 'inhibit-pid', json.dumps([os.getpid(), process(os.getpid())[2], token]))
  while True:
    signal.pause()


def start_inhibitor(directory):
  stop_inhibitor(directory)
  directory.mkdir(mode=0o700)
  token = secrets.token_hex(16)
  publish(directory / 'launch-control', token)
  owner = f'update:{token}'
  committed = False
  launcher = None
  detached = False
  def interrupted(number, frame):
    raise SystemExit(128 + number)
  for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(number, interrupted)
  try:
    command = ['systemd-inhibit', '--what=sleep:idle', '--who=monarch-update',
      f'--why=Monarch update in progress [{token}]', '--mode=block',
      '/usr/bin/setpriv', '--reuid', str(os.getuid()), '--regid', str(os.getgid()), '--clear-groups',
      '/usr/bin/python3', '-I', str(Path(__file__).resolve()), 'hold', str(directory), token]
    if os.geteuid() != 0:
      if os.isatty(0) or os.environ.get('MONARCH_UPDATE_SUDO_SESSION') == '1':
        options = ['sudo', '-N', '-b']
        if not os.isatty(0):
          options.append('-n')
        launcher = subprocess.Popen(options + ['--'] + command, stdout=subprocess.DEVNULL,
          stderr=subprocess.DEVNULL, close_fds=True)
        detached = True
      else:
        launcher = subprocess.Popen(['pkexec'] + command, stdin=subprocess.DEVNULL,
          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
    else:
      launcher = subprocess.Popen(command, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
    deadline = time.monotonic() + 60
    while True:
      try:
        record = inhibitor_record(directory)
        if record[2] == token and identity_matches(record):
          break
      except FileNotFoundError:
        pass
      status = launcher.poll()
      if (status is not None and (status != 0 or not detached)) or time.monotonic() >= deadline:
        raise RuntimeError('The update sleep inhibitor did not become ready.')
      time.sleep(0.05)
    publish(directory / 'idle-owner', owner)
    # A pre-existing or newer user choice belongs to Noctalia, not this update.
    subprocess.run(['monarch-toggle-idle', 'claim', owner], stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL)
    committed = True
  finally:
    if not committed:
      try:
        stop_inhibitor(directory)
      finally:
        if launcher and launcher.poll() is None:
          launcher.terminate()


def main():
  action, *args = sys.argv[1:]
  if action == 'hold' and len(args) == 2:
    return hold(Path(args[0]), args[1])
  base = state_base()
  if action == 'held':
    return 0 if lock_held(base / 'monarch-update.lock') else 1
  if action == 'run':
    return run_locked(base, args)
  if action not in ('start', 'stop') or args:
    raise RuntimeError('Expected held, run, start or stop.')
  # Lock the stable base, not the state directory removed by stop.
  fd = os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
  try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    directory = base / 'monarch-update-stay-awake'
    if action == 'start':
      start_inhibitor(directory)
    else:
      stop_inhibitor(directory)
  finally:
    os.close(fd)
  return 0


if __name__ == '__main__':
  try:
    sys.exit(main())
  except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
    print(f'Monarch update: {error}', file=sys.stderr)
    sys.exit(1)
