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
if (( $(cat "$STREAM_COUNT") >= $(wc -l <"$STREAM_STATES") )); then
  kill -TERM "$PPID"
fi
STUB
chmod +x "$test_tmp/bin/monarch-update-available" "$test_tmp/bin/sleep"

run_stream() {
  rm -f "$STREAM_COUNT" "$STREAM_SLEEPS"
  stream_status=0
  bash "$ROOT/default/noctalia/indicators/monarch-update.sh" >"$test_tmp/stream" || stream_status=$?
  ((stream_status == 143)) || fail "stream did not stop after the fixture"
}

printf '0\n2\n0\n1\n' >"$STREAM_STATES"
run_stream
[[ $(wc -l <"$test_tmp/stream") == 2 ]] || fail "failed checks clear or duplicate the update badge"
grep -q 'Monarch update available' "$test_tmp/stream" || fail "stream does not show available updates"
[[ $(tail -n 1 "$test_tmp/stream") == '{}' ]] || fail "confirmed up-to-date check does not clear the badge"
[[ $(<"$STREAM_SLEEPS") == $'600\n600\n600\n21600' ]] || fail "stream does not use the expected retry cadence"
pass "the indicator preserves its badge on failure and clears it only after a successful check"

printf '2\n1\n' >"$STREAM_STATES"
run_stream
[[ $(<"$test_tmp/stream") == '{}' ]] || fail "initial failed checks display an update badge"
[[ $(<"$STREAM_SLEEPS") == $'600\n21600' ]] || fail "initial failures defer checks for six hours"
pass "initial errors stay hidden but retry sooner than successful idle checks"
