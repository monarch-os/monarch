#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/systemd"
export PACMAN_TEST_LOG="$test_tmp/calls"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"

cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >>"$PACMAN_TEST_LOG"
exit "${PACMAN_TEST_STATUS:-0}"
STUB
chmod +x "$test_tmp/bin/sudo"

[[ -f $ROOT/bin/monarch-update-pacman ]] || fail "the update executor exists"
sed "s|/run/systemd/system|$test_tmp/systemd|g" \
  "$ROOT/bin/monarch-update-pacman" >"$test_tmp/executor"

LC_ALL=C bash "$test_tmp/executor" -Syu -- 'package with spaces'
expected=$'</usr/bin/env>\n<MONARCH_UPDATE_PACMAN=1>\n<LC_ALL=C>\n</usr/bin/systemd-run>\n<--scope>\n<--quiet>\n<--collect>\n</usr/bin/pacman>\n<-Syu>\n<-->\n<package with spaces>'
[[ $(<"$PACMAN_TEST_LOG") == "$expected" ]] || fail "transactions leave the user manager without losing argv or locale"
pass "systemd transactions use a system scope and preserve argv, locale and the ALPM marker"

: >"$PACMAN_TEST_LOG"
if PACMAN_TEST_STATUS=42 bash "$test_tmp/executor" -Su; then
  fail "a failed scope or transaction reports success"
else
  result=$?
fi
((result == 42)) || fail "the executor changes the failing exit status"
(( $(grep -c '^</usr/bin/env>$' "$PACMAN_TEST_LOG") == 1 )) || fail "a failed scope retries unprotected"
pass "failed scope creation or Pacman execution is never retried outside protection"

rmdir "$test_tmp/systemd"
: >"$PACMAN_TEST_LOG"
env -u LC_ALL bash "$test_tmp/executor" -S --needed monarch
[[ $(<"$PACMAN_TEST_LOG") == $'</usr/bin/env>\n<MONARCH_UPDATE_PACMAN=1>\n</usr/bin/pacman>\n<-S>\n<--needed>\n<monarch>' ]] ||
  fail "a non-systemd environment cannot bootstrap packages directly"
pass "bootstrap outside systemd retains direct execution without inventing a locale"

ln -s "$test_tmp" "$test_tmp/systemd"
: >"$PACMAN_TEST_LOG"
env -u LC_ALL bash "$test_tmp/executor" -S monarch
! grep -q '^</usr/bin/systemd-run>$' "$PACMAN_TEST_LOG" || fail "a symlink claims an active system manager"
pass "the systemd marker must be a real directory"
