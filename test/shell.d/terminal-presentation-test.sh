#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PRESENTATION_LOG="$test_tmp/calls"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"

cat >"$test_tmp/bin/setsid" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$test_tmp/bin/uwsm-app" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >>"$PRESENTATION_LOG"
while (($#)); do
  if [[ $1 == bash && $2 == -c ]]; then
    exec "$@"
  fi
  shift
done
exit 99
STUB
cat >"$test_tmp/bin/monarch-show-logo" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$test_tmp/bin/monarch-show-done" <<'STUB'
#!/bin/bash
printf 'result=%s\n' "${1:-missing}" >>"$PRESENTATION_LOG"
exit 0
STUB
chmod +x "$test_tmp/bin/"*

for status in 0 1 42 130; do
  : >"$PRESENTATION_LOG"
  bash "$ROOT/bin/monarch-launch-floating-terminal-with-presentation" \
    --app-id=org.monarch.test "bash -c 'exit $status'"
  if ((status == 130)); then
    ! grep -q '^result=' "$PRESENTATION_LOG" || fail "cancellation waits for another keypress"
  else
    grep -qx "result=$status" "$PRESENTATION_LOG" || fail "presentation hides command status $status"
  fi
  grep -qx '<--app-id=org.monarch.test>' "$PRESENTATION_LOG" || fail "presentation drops the window identity"
done
pass "presentation reports success and failures while skipping cancellation"

grep -qF 'monarch-show-done $?' "$ROOT/bin/monarch-pkg-install" || fail "package installation hides failures"
grep -qF 'monarch-show-done $?' "$ROOT/bin/monarch-pkg-remove" || fail "package removal hides failures"
grep -qF 'monarch-show-done $code' "$ROOT/bin/monarch-pkg-aur-install" || fail "AUR installation hides failures"
pass "package selectors pass transaction failures to the presentation"

python3 - "$ROOT/bin/monarch-show-done" <<'PY'
import os
import pty
import select
import signal
import sys
import time

for code, message in ((0, b"Done!"), (1, b"Failed (exit code 1)!"), (42, b"Failed (exit code 42)!")):
    pid, terminal = pty.fork()
    if pid == 0:
        os.dup2(os.open("/dev/null", os.O_WRONLY), 1)
        os.execv("/bin/bash", ["bash", sys.argv[1], str(code)])
    output = b""
    completed = False
    try:
        deadline = time.monotonic() + 5
        while b"Press any key" not in output and time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.1)[0]:
                output += os.read(terminal, 4096)
        assert message in output, (code, output)
        if code:
            assert b"Done!" not in output, output
        assert os.waitpid(pid, os.WNOHANG) == (0, 0), "prompt did not wait"
        os.write(terminal, b"x")
        while time.monotonic() < deadline:
            finished, status = os.waitpid(pid, os.WNOHANG)
            if finished:
                completed = True
                assert os.waitstatus_to_exitcode(status) == 0
                break
            time.sleep(0.01)
        assert completed, "keypress did not close the prompt"
    finally:
        if not completed:
            try:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            except ProcessLookupError:
                pass
        os.close(terminal)
PY
pass "the actual terminal prompt displays success or failure even with redirected stdout"

output=$(/usr/bin/setsid --wait bash "$ROOT/bin/monarch-show-done" 1 </dev/null)
[[ -z $output ]] || fail "a headless result writes an invisible prompt"
pass "headless completion never waits"
