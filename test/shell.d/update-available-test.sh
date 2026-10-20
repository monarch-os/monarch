#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export UPDATE_FIXTURE="$test_tmp/updates" UPDATE_DB_RECORD="$test_tmp/db"
export UPDATE_FORBIDDEN_LOG="$test_tmp/forbidden"
export TMPDIR="$test_tmp"
: >"$UPDATE_FIXTURE"

cat >"$test_tmp/bin/monarch-cmd-missing" <<'STUB'
#!/bin/bash
[[ $* == 'checkupdates fakeroot' ]] || exit 99
exit "${MISSING_COMMAND_STATUS:-1}"
STUB
cat >"$test_tmp/bin/checkupdates" <<'STUB'
#!/bin/bash
[[ $* == '--nocolor' && $LC_ALL == C ]] || exit 99
[[ -d $CHECKUPDATES_DB && $CHECKUPDATES_DB == "$TMPDIR"/tmp.* ]] || exit 99
printf '%s\n' "$CHECKUPDATES_DB" >"$UPDATE_DB_RECORD"
cat "$UPDATE_FIXTURE"
exit "${CHECKUPDATES_STATUS:-0}"
STUB
for command in git sudo pacman; do
  cat >"$test_tmp/bin/$command" <<'STUB'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$UPDATE_FORBIDDEN_LOG"
exit 99
STUB
done
chmod +x "$test_tmp/bin/"*

run_check() {
  status=0
  bash "$ROOT/bin/monarch-update-available" >"$test_tmp/out" 2>"$test_tmp/err" || status=$?
}

printf 'monarch 2026.10.0-2 -> 2026.10.1-2\n' >"$UPDATE_FIXTURE"
run_check
((status == 0)) || fail "published Monarch upgrade is detected"
grep -q '2026.10.0-2 -> 2026.10.1-2' "$test_tmp/out" || fail "upgrade identifies both versions"
first_db=$(<"$UPDATE_DB_RECORD")
[[ ! -e $first_db ]] || fail "temporary database is cleaned after an available update"
pass "published Monarch upgrades use an isolated database without Git or sudo"

printf 'monarch-settings 1 -> 2\nlinux 6.1 -> 6.2\n' >"$UPDATE_FIXTURE"
run_check
((status == 1)) || fail "unrelated package upgrades raise the Monarch badge"
[[ $(<"$UPDATE_DB_RECORD") != "$first_db" ]] || fail "checks share mutable package databases"
[[ ! -e $(<"$UPDATE_DB_RECORD") ]] || fail "temporary database is cleaned after unrelated updates"
pass "unrelated upgrades and similarly named packages do not raise the badge"

export CHECKUPDATES_STATUS=2
: >"$UPDATE_FIXTURE"
run_check
((status == 1)) || fail "checkupdates no-upgrade status is translated"
pass "no-upgrade status is distinct from a repository failure"

for check_status in 1 124 127; do
  export CHECKUPDATES_STATUS=$check_status
  run_check
  ((status == 2)) || fail "failed or timed-out checks report an error"
  [[ ! -s $test_tmp/out ]] || fail "a failed check claims availability"
  [[ ! -e $(<"$UPDATE_DB_RECORD") ]] || fail "failed checks leave a temporary database"
done
pass "repository errors, timeouts and command failures fail distinctly and clean up"

export CHECKUPDATES_STATUS=0
printf 'monarch 2026.10.0-2 ->\n' >"$UPDATE_FIXTURE"
run_check
((status == 2)) || fail "malformed Monarch update information is accepted"
pass "malformed update information cannot claim a successful check"

export MISSING_COMMAND_STATUS=0
rm "$UPDATE_DB_RECORD"
run_check
((status == 2)) || fail "missing dependencies are treated as up to date"
[[ ! -e $UPDATE_DB_RECORD ]] || fail "missing dependencies still trigger a repository check"
[[ ! -e $UPDATE_FORBIDDEN_LOG ]] || fail "checks invoke Git, sudo or the system pacman database"
pass "missing check dependencies fail before database creation"

export STREAM_STATES="$test_tmp/states" STREAM_COUNT="$test_tmp/count"
export STREAM_SLEEPS="$test_tmp/sleeps"
export STREAM_NETWORK="full"
cat >"$test_tmp/bin/nmcli" <<'STUB'
#!/bin/bash
[[ $* == '-t -f STATE,CONNECTIVITY general' && $LC_ALL == "C" ]] || exit 99
if [[ -n ${STREAM_NETWORK_AFTER_CHECK:-} && -f $STREAM_COUNT ]]; then
  connectivity=$STREAM_NETWORK_AFTER_CHECK
elif [[ -n ${STREAM_NETWORK_STATES:-} ]]; then
  count=0
  [[ ! -f $STREAM_SLEEPS ]] || count=$(wc -l <"$STREAM_SLEEPS")
  connectivity=$(sed -n "$((count + 1))p" "$STREAM_NETWORK_STATES")
else
  connectivity=$STREAM_NETWORK
fi
printf '%s:%s\n' "${STREAM_CONNECTION_STATE:-connected}" "$connectivity"
exit "${STREAM_NETWORK_STATUS:-0}"
STUB
cat >"$test_tmp/bin/monarch-update-available" <<'STUB'
#!/bin/bash
count=$(cat "$STREAM_COUNT" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" >"$STREAM_COUNT"
exit "$(sed -n "${count}p" "$STREAM_STATES")"
STUB
cat >"$test_tmp/bin/sleep" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >>"$STREAM_SLEEPS"
if (( $(wc -l <"$STREAM_SLEEPS") >= $(wc -l <"$STREAM_STATES") )); then
  kill -TERM "$PPID"
fi
STUB
chmod +x "$test_tmp/bin/monarch-update-available" "$test_tmp/bin/sleep" "$test_tmp/bin/nmcli"

run_stream() {
  rm -f "$STREAM_COUNT" "$STREAM_SLEEPS"
  stream_status=0
  bash "$ROOT/default/noctalia/indicators/monarch-update.sh" >"$test_tmp/stream" || stream_status=$?
  ((stream_status == 143)) || fail "stream did not stop after the fixture"
}

printf '0\n2\n0\n1\n' >"$STREAM_STATES"
run_stream
[[ $(wc -l <"$test_tmp/stream") == 4 ]] || fail "indicator does not report state transitions"
grep -q 'Monarch update available' "$test_tmp/stream" || fail "stream does not show available updates"
grep -q '"text":"".*"textColor":"on_surface_variant"' "$test_tmp/stream" || fail "online failures lack a neutral warning triangle"
grep -q '"text":"".*"textColor":"on_surface"' "$test_tmp/stream" || fail "available updates do not restore the normal color"
[[ $(tail -n 1 "$test_tmp/stream") == '{}' ]] || fail "confirmed up-to-date check does not clear the badge"
[[ $(<"$STREAM_SLEEPS") == $'600\n600\n600\n21600' ]] || fail "stream does not use the expected retry cadence"
pass "online failures show a neutral warning triangle and successful checks restore the badge"

printf '2\n1\n' >"$STREAM_STATES"
run_stream
grep -q 'Could not check for updates' "$test_tmp/stream" || fail "initial online failure is not explained"
[[ $(tail -n 1 "$test_tmp/stream") == '{}' ]] || fail "successful idle check does not clear the warning"
[[ $(<"$STREAM_SLEEPS") == $'600\n21600' ]] || fail "initial failures defer checks for six hours"
pass "initial online errors show a warning and retry sooner than successful idle checks"

for network in none portal limited unknown; do
  export STREAM_NETWORK=$network
  run_stream
  [[ $(<"$test_tmp/stream") == '{}' ]] || fail "$network connectivity displays a warning"
  [[ ! -f $STREAM_COUNT ]] || fail "$network connectivity triggers a repository check"
  [[ $(<"$STREAM_SLEEPS") == $'60\n60' ]] || fail "$network connectivity does not retry promptly"
done
pass "offline, captive, limited and unknown connectivity stay hidden without repository checks"

export STREAM_NETWORK=full STREAM_NETWORK_STATUS=10
run_stream
[[ $(<"$test_tmp/stream") == '{}' && ! -f $STREAM_COUNT ]] || fail "unavailable NetworkManager triggers an online warning"
unset STREAM_NETWORK_STATUS
pass "an unavailable connectivity service cannot raise an online warning"

export STREAM_CONNECTION_STATE=disconnected
run_stream
[[ $(<"$test_tmp/stream") == '{}' && ! -f $STREAM_COUNT ]] || fail "a stale connectivity result raises an offline warning"
unset STREAM_CONNECTION_STATE
pass "a disconnected link stays hidden even if the cached connectivity result is full"

export STREAM_NETWORK_AFTER_CHECK=none
run_stream
[[ $(<"$test_tmp/stream") == '{}' ]] || fail "connection loss during a check raises a warning"
[[ $(<"$STREAM_COUNT") == 1 ]] || fail "disconnected stream continues repository checks"
[[ $(<"$STREAM_SLEEPS") == $'60\n60' ]] || fail "connection loss delays the next connectivity check"
unset STREAM_NETWORK_AFTER_CHECK
pass "connection loss during a failed check hides the indicator and retries promptly"

export STREAM_NETWORK_STATES="$test_tmp/networks"
printf 'none\nfull\nfull\n' >"$STREAM_NETWORK_STATES"
printf '0\n1\n1\n' >"$STREAM_STATES"
run_stream
[[ $(head -n 1 "$test_tmp/stream") == '{}' ]] || fail "offline boot displays an indicator"
grep -q 'Monarch update available' "$test_tmp/stream" || fail "connecting does not trigger an update check"
[[ $(<"$STREAM_SLEEPS") == $'60\n600\n21600' ]] || fail "reconnection does not restore normal check intervals"
pass "connecting after an offline boot checks updates on the next one-minute retry"

printf 'full\nnone\nfull\n' >"$STREAM_NETWORK_STATES"
printf '2\n0\n1\n' >"$STREAM_STATES"
run_stream
[[ $(sed -n '2p' "$test_tmp/stream") == '{}' ]] || fail "disconnecting leaves an online warning visible"
[[ $(tail -n 1 "$test_tmp/stream") == *'Monarch update available'* ]] || fail "reconnecting leaves a stale warning"
pass "disconnecting clears an online warning and reconnecting restores confirmed availability"
