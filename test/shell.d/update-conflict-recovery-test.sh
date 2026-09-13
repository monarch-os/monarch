#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

command -v script >/dev/null || fail "script is required for terminal-boundary tests"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/tmp"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"

case "$*" in
  '/usr/bin/env LC_ALL=C MONARCH_UPDATE_PACMAN=1 /usr/bin/pacman -Syyu --noconfirm')
    exec "$PACMAN_STUB" -Syyu --noconfirm
    ;;
  '/usr/bin/env MONARCH_UPDATE_PACMAN=1 /usr/bin/pacman -Su')
    exec "$PACMAN_STUB" -Su
    ;;
  *)
    echo "unexpected privileged command: $*" >&2
    exit 97
    ;;
esac
STUB

cat >"$stub_bin/pacman-stub" <<'STUB'
#!/bin/bash
attempt=$(($(<"$PACMAN_ATTEMPTS") + 1))
echo "$attempt" >"$PACMAN_ATTEMPTS"
{
  printf 'args %s\n' "$*"
  for fd in 0 1 2; do
    if [[ -t $fd ]]; then
      printf 'tty%s yes\n' "$fd"
    else
      printf 'tty%s no\n' "$fd"
    fi
  done
} >>"$PACMAN_CALLS"

if [[ $PACMAN_CASE == "clean" || $attempt == 2 ]]; then
  echo 'upgrade complete'
  exit 0
fi

case "$PACMAN_CASE" in
  package)
    printf '\e[1;31merror: \e[0munresolvable package conflicts detected\n' >&2
    printf '\e[1;31merror: \e[0mfailed to prepare transaction (conflicting dependencies)\n' >&2
    ;;
  file)
    echo 'error: failed to commit transaction (conflicting files)' >&2
    echo "monarch: $CONFLICT_PATH exists in filesystem" >&2
    ;;
  unrelated)
    echo 'error: failed retrieving file from mirror' >&2
    ;;
esac
exit "$FIRST_STATUS"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/pacman-stub"

for command in monarch-update-system-pkgs-when-conflicted mkdir mv; do
  cat >"$stub_bin/$command" <<'STUB'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >>"$POISON_CALLS"
exit 96
STUB
done
chmod +x "$stub_bin"/*

prepare_case() {
  echo 0 >"$test_tmp/attempts"
  : >"$test_tmp/calls"
  : >"$test_tmp/sudo-calls"
  : >"$test_tmp/poison-calls"
  rm -f "$test_tmp/tmp"/*
}

update_env() {
  printf '%s\n' \
    "PACMAN_CASE=$PACMAN_CASE" \
    "PACMAN_STUB=$stub_bin/pacman-stub" \
    "PACMAN_ATTEMPTS=$test_tmp/attempts" \
    "PACMAN_CALLS=$test_tmp/calls" \
    "SUDO_CALLS=$test_tmp/sudo-calls" \
    "POISON_CALLS=$test_tmp/poison-calls" \
    "CONFLICT_PATH=$test_tmp/live.conf" \
    "FIRST_STATUS=${FIRST_STATUS:-1}" \
    "MONARCH_REPLACED_DIR=$test_tmp/replaced" \
    "TMPDIR=$test_tmp/tmp" \
    "MONARCH_UPDATE_UNATTENDED=${MONARCH_UPDATE_UNATTENDED:-}" \
    "PATH=$stub_bin:$ROOT/bin:$PATH"
}

run_headless() {
  mapfile -t environment < <(update_env)
  env "${environment[@]}" bash "$ROOT/bin/monarch-update-system-pkgs" \
    </dev/null >"$test_tmp/out" 2>"$test_tmp/err"
}

run_on_terminal() {
  mapfile -t environment < <(update_env)
  env "${environment[@]}" \
    script -qec "bash '$ROOT/bin/monarch-update-system-pkgs' ${1:-}" \
      "$test_tmp/transcript" >/dev/null 2>&1
}

call_line() {
  awk -v call="$1" -v key="$2" \
    '$1 == "args" { n++ } n == call && $1 == key { sub(/^[^ ]+ /, ""); print }' \
    "$test_tmp/calls"
}

assert_report_removed() {
  [[ -z $(find "$test_tmp/tmp" -mindepth 1 -print -quit) ]] ||
    fail "the package update leaks its error report"
}

PACMAN_CASE=clean
prepare_case
run_headless || fail "a clean package update fails"
[[ $(<"$test_tmp/calls") == $'args -Syyu --noconfirm\ntty0 no\ntty1 no\ntty2 no' ]] ||
  fail "a clean package update changes the ordinary transaction"
assert_report_removed
pass "clean package updates run one ordinary transaction"

PACMAN_CASE=package
prepare_case
run_on_terminal || fail "a package conflict is not returned to the user"
(( $(<"$test_tmp/attempts") == 2 )) || fail "a package conflict does not get an interactive retry"
[[ $(call_line 1 args) == "-Syyu --noconfirm" ]] || fail "the initial update arguments changed"
[[ $(call_line 2 args) == "-Su" ]] || fail "the retry refreshes databases or answers the conflict"
[[ $(call_line 2 tty0) == "yes" && $(call_line 2 tty2) == "yes" ]] ||
  fail "the interactive retry cannot show and receive the answer"
! grep -Eq -- '--overwrite|--ask' "$test_tmp/calls" ||
  fail "a package conflict is resolved without the user's decision"
assert_report_removed
pass "package conflicts are handed back to the person running the update"

prepare_case
run_on_terminal '>/dev/null' || fail "redirected progress disables an answerable retry"
(( $(<"$test_tmp/attempts") == 2 )) || fail "redirected stdout prevents an interactive retry"
pass "only Pacman's question and answer streams must remain attached"

prepare_case
if run_on_terminal '2>/dev/null'; then
  fail "a package conflict prompts where its question is hidden"
fi
(( $(<"$test_tmp/attempts") == 1 )) || fail "hidden stderr still triggers a retry"
pass "a hidden question is never retried interactively"

prepare_case
if run_headless; then
  fail "a package conflict passes for a completed headless update"
else
  update_status=$?
fi
(( update_status == 1 )) || fail "a headless conflict loses Pacman's status"
(( $(<"$test_tmp/attempts") == 1 )) || fail "a headless conflict triggers a retry"
grep -q 'monarch update' "$test_tmp/err" || fail "a headless conflict omits recovery guidance"
assert_report_removed
pass "headless package conflicts report how to continue"

prepare_case
if MONARCH_UPDATE_UNATTENDED=1 run_on_terminal; then
  fail "an unattended update reports a package conflict as resolved"
else
  update_status=$?
fi
(( update_status == 1 )) || fail "an unattended conflict loses Pacman's status"
(( $(<"$test_tmp/attempts") == 1 )) || fail "an unattended update prompts"
pass "unattended package updates never wait for an answer"

PACMAN_CASE=file
FIRST_STATUS=42
prepare_case
printf 'original contents\n' >"$test_tmp/live.conf"
original_inode=$(stat -c %i "$test_tmp/live.conf")
if run_on_terminal; then
  fail "a filesystem conflict reports a successful update"
else
  update_status=$?
fi
(( update_status == 42 )) || fail "a filesystem conflict loses Pacman's status"
(( $(<"$test_tmp/attempts") == 1 )) || fail "a filesystem conflict retries Pacman"
(( $(wc -l <"$test_tmp/sudo-calls") == 1 )) ||
  fail "a filesystem conflict authorizes another privileged command"
[[ ! -s $test_tmp/poison-calls ]] || fail "a filesystem conflict reaches a mover or retired handler"
[[ $(stat -c %i "$test_tmp/live.conf") == "$original_inode" ]] ||
  fail "a filesystem conflict replaces the live path"
grep -qx 'original contents' "$test_tmp/live.conf" || fail "a filesystem conflict changes the live path"
[[ ! -e $test_tmp/replaced ]] || fail "a filesystem conflict creates a quarantine"
grep -q 'exists in filesystem' "$test_tmp/transcript" || fail "Pacman's conflict report is hidden"
assert_report_removed
pass "filesystem conflicts fail without moving live paths"

PACMAN_CASE=unrelated
FIRST_STATUS=23
prepare_case
if run_on_terminal; then
  fail "an unrelated Pacman failure reports success"
else
  update_status=$?
fi
(( update_status == 23 )) || fail "an unrelated Pacman failure loses its status"
(( $(<"$test_tmp/attempts") == 1 )) || fail "an unrelated Pacman failure is retried"
(( $(wc -l <"$test_tmp/sudo-calls") == 1 )) ||
  fail "an unrelated Pacman failure authorizes another privileged command"
assert_report_removed
pass "only package conflicts trigger an interactive retry"
