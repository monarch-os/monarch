#!/bin/bash

# Guards the niri socket discovery in monarch-hw-recover-internal-monitor.
#
# The watcher is a safety net for a laptop left with no display at all, and its
# only failure mode is silence: a socket it cannot reach costs one `niri msg`
# that fails, then a loop that spins forever finding nothing to recover.
#
# Needs no niri: a copy of /bin/sleep named `niri` gives /proc/<pid>/comm the
# name the discovery matches on, and python3 binds the socket files.
#
# Run: bash test/monarch-niri-socket-test.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WATCHER="$ROOT/bin/monarch-hw-recover-internal-monitor"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

check() {
  [[ $2 == "$3" ]] || fail "$1: expected [$3], got [$2]"
  pass "$1"
}

TMP=$(mktemp -d)
FAKE_NIRI_PID=""
cleanup() {
  [[ -n $FAKE_NIRI_PID ]] && kill "$FAKE_NIRI_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# Spawned with no NIRI_SOCKET so the host's own session cannot answer for the
# stand-in through anything the discovery might read.
unset NIRI_SOCKET
cp /bin/sleep "$TMP/niri"
"$TMP/niri" 300 &
FAKE_NIRI_PID=$!

export XDG_RUNTIME_DIR="$TMP"
LIVE_SOCKET="$TMP/niri.wayland-1.$FAKE_NIRI_PID.sock"
STALE_SOCKET="$TMP/niri.wayland-1.4194303.sock" # above pid_max, so never live
python3 - "$LIVE_SOCKET" "$STALE_SOCKET" <<'PY'
import socket, sys
for path in sys.argv[1:]:
    socket.socket(socket.AF_UNIX, socket.SOCK_STREAM).bind(path)
PY

source "$WATCHER"

pgrep() { echo "$FAKE_NIRI_PID"; }

unset NIRI_SOCKET
ensure_socket
check "an unset NIRI_SOCKET is discovered from the running pid" "$NIRI_SOCKET" "$LIVE_SOCKET"

export NIRI_SOCKET="$STALE_SOCKET"
ensure_socket
check "a socket left by a dead session is replaced" "$NIRI_SOCKET" "$LIVE_SOCKET"

export NIRI_SOCKET="$TMP/gone.sock"
ensure_socket
check "a path that is not a socket is replaced" "$NIRI_SOCKET" "$LIVE_SOCKET"

export NIRI_SOCKET=""
ensure_socket
check "an empty NIRI_SOCKET is not a fatal expansion" "$NIRI_SOCKET" "$LIVE_SOCKET"

pgrep() { return 1; }
export NIRI_SOCKET="$LIVE_SOCKET"
ensure_socket
check "a live socket is kept without consulting pgrep" "$NIRI_SOCKET" "$LIVE_SOCKET"

unset NIRI_SOCKET
ensure_socket && fail "no niri running must not report success"
pass "no niri running is reported as a failure"

pgrep() { echo 4194302; } # live-looking, but no socket of that name exists
unset NIRI_SOCKET
ensure_socket && fail "a pid with no socket must not report success"
[[ ${NIRI_SOCKET:-} != *'*'* ]] || fail "an unmatched glob leaked into NIRI_SOCKET"
pass "a running pid with no socket of its own is reported as a failure"

# $$ is alive and its comm is `bash`, standing in for the pid a recycled socket
# name would point at.
socket_live "$STALE_SOCKET" && fail "a socket whose pid is gone must not be live"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$TMP/niri.wayland-1.$$.sock"
socket_live "$TMP/niri.wayland-1.$$.sock" && fail "a socket whose pid is not niri must not be live"
pass "socket_live rejects a dead pid and a pid that is not niri"

# The bug this replaced: the name was read from the environment block the
# process was exec'd with, where a socket created later cannot appear.
grep -qE '^[^#]*/environ' "$WATCHER" && fail "the socket must not be looked up in /proc/<pid>/environ"
pass "the socket name is rebuilt, not read from /proc/<pid>/environ"
