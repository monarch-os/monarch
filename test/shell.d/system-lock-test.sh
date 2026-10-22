#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/recorder" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$LOCK_TEST_CALLS"
case ${0##*/} in
  noctalia) exit "${LOCK_TEST_STATUS:-0}" ;;
  pgrep | pkill) exit 1 ;;
esac
EOF
chmod +x "$test_tmp/bin/recorder"
for command in noctalia pgrep pkill sleep monarch-brightness-keyboard; do
  ln -s recorder "$test_tmp/bin/$command"
done

ROOT="$ROOT" LOCK_TEST_BIN="$test_tmp/bin" LOCK_TEST_CALLS="$test_tmp/calls" python3 - <<'PY'
import os
from pathlib import Path
import subprocess

root = Path(os.environ['ROOT'])
calls = Path(os.environ['LOCK_TEST_CALLS'])

def run(status, lock_only):
  calls.write_text('')
  env = {**os.environ, 'PATH': os.environ['LOCK_TEST_BIN'],
         'LOCK_TEST_STATUS': str(status), 'MONARCH_LOCK_ONLY': str(lock_only).lower()}
  return subprocess.run(['/bin/bash', str(root / 'bin/monarch-system-lock')],
                        env=env, capture_output=True, text=True)

for lock_only in (True, False):
  for status in (1, 127):
    result = run(status, lock_only)
    assert result.returncode == status, (status, lock_only, result.returncode)
    assert result.stderr.strip(), 'a failed lock request must have a diagnostic'
    assert 'noctalia msg session lock' in calls.read_text()
  result = run(0, lock_only)
  assert result.returncode == 0, result
  assert not result.stderr, result.stderr
  assert 'pkill -f [o]rg.monarch.screensaver' in calls.read_text()
  assert ('monarch-brightness-keyboard off' in calls.read_text()) == (not lock_only)
print('ok - lock errors survive cleanup in manual and lock-only modes')
print('ok - missing cleanup targets do not turn an accepted lock request into a failure')

Path(os.environ['LOCK_TEST_BIN'], 'noctalia').unlink()
result = run(0, True)
assert result.returncode == 127, result
assert result.stderr.strip(), 'a missing Noctalia command must not report success'
print('ok - an unavailable Noctalia command fails without contacting the desktop')
PY
