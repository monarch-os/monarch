#!/bin/bash

# Guards the niri socket discovery in monarch-hw-recover-internal-monitor.
#
# The watcher is a safety net for a laptop left with no display at all, and its
# only failure mode is silence: a socket it cannot reach costs one `niri msg`
# that fails, then a loop that spins forever finding nothing to recover.
#
# Needs no niri: a copy of /bin/sleep named `niri` gives /proc/<pid>/comm the
# name the discovery matches on, and perl binds the socket files — nothing in
# bash or coreutils can, and perl is present on both a bare CI image and a
# Monarch desktop, which python3 is not.
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

# Runs the discovery and asserts where it landed. A non-zero return is its own
# failure: called bare, set -e would end the run with no output at all — which
# is exactly what the implementation this replaced does here.
discovers() {
  ensure_socket || fail "$1: discovery returned non-zero"
  check "$1" "$NIRI_SOCKET" "$2"
}

# Captured before the fixture takes the variable over, for the live check at
# the end.
HOST_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
HOST_NIRI_PID=$(command pgrep -x niri | head -n1 || true)

# pids stop one below pid_max, so this one is never a running process.
DEAD_PID=$(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304)

make_socket() {
  perl -MSocket -e '
    socket(S, AF_UNIX, SOCK_STREAM, 0) or die $!;
    bind(S, sockaddr_un($ARGV[0])) or die $!;
  ' "$1"
}

command -v perl >/dev/null || fail "perl is required to create the socket files this exercises"

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
STALE_SOCKET="$TMP/niri.wayland-1.$DEAD_PID.sock"
make_socket "$LIVE_SOCKET"
make_socket "$STALE_SOCKET"

source "$WATCHER"

pgrep() { echo "$FAKE_NIRI_PID"; }

unset NIRI_SOCKET
discovers "an unset NIRI_SOCKET is discovered from the running pid" "$LIVE_SOCKET"

export NIRI_SOCKET="$STALE_SOCKET"
discovers "a socket left by a dead session is replaced" "$LIVE_SOCKET"

export NIRI_SOCKET="$TMP/gone.sock"
discovers "a path that is not a socket is replaced" "$LIVE_SOCKET"

export NIRI_SOCKET=""
discovers "an empty NIRI_SOCKET is not a fatal expansion" "$LIVE_SOCKET"

pgrep() { return 1; }
export NIRI_SOCKET="$LIVE_SOCKET"
discovers "a live socket is kept without consulting pgrep" "$LIVE_SOCKET"

unset NIRI_SOCKET
ensure_socket && fail "no niri running must not report success"
pass "no niri running is reported as a failure"

pgrep() { echo 1; } # pid 1 is always there, and the fixture gave it no socket
unset NIRI_SOCKET
ensure_socket && fail "a pid with no socket must not report success"
[[ ${NIRI_SOCKET:-} != *'*'* ]] || fail "an unmatched glob leaked into NIRI_SOCKET"
pass "a running pid with no socket of its own is reported as a failure"

# $$ is alive and its comm is `bash`, standing in for the pid a recycled socket
# name would point at.
socket_live "$STALE_SOCKET" && fail "a socket whose pid is gone must not be live"
make_socket "$TMP/niri.wayland-1.$$.sock"
socket_live "$TMP/niri.wayland-1.$$.sock" && fail "a socket whose pid is not niri must not be live"
pass "socket_live rejects a dead pid and a pid that is not niri"

# The bug this replaced: the name was read from the environment block the
# process was exec'd with, where a socket created later cannot appear.
grep -qE '^[^#]*/environ' "$WATCHER" && fail "the socket must not be looked up in /proc/<pid>/environ"
pass "the socket name is rebuilt, not read from /proc/<pid>/environ"

# Everything above runs against a stand-in, which proves the logic but assumes
# the socket naming. Only a real session can confirm that assumption, so check
# it when one is there and say so when it is not — CI never has one.
if [[ -n $HOST_NIRI_PID ]]; then
  host_socket=$(printf '%s\n' "$HOST_RUNTIME_DIR"/niri.*."$HOST_NIRI_PID".sock | head -n1)
  [[ -S $host_socket ]] || fail "the running niri ($HOST_NIRI_PID) has no socket under the name this expects"
  pass "the running niri names its socket as the discovery expects ($host_socket)"
else
  pass "no niri session to check the socket naming against (skipped)"
fi
