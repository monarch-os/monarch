#!/bin/bash

set -euo pipefail

case "${0##*/}" in
blkid)
  printf '%s' "$LUKS_DRIVES"
  exit 0
  ;;
monarch-drive-select)
  printf '%s' "$LUKS_SELECTED"
  exit "$LUKS_SELECT_STATUS"
  ;;
gum)
  printf '%s\n' "$*" >>"$LUKS_CASE/prompts"
  [[ ! ${new_password+x} ]] || printf 'new_password\n' >>"$LUKS_CASE/environment-leaks"
  [[ ! ${confirmation+x} ]] || printf 'confirmation\n' >>"$LUKS_CASE/environment-leaks"
  if [[ ! -e $LUKS_CASE/prompted ]]; then
    touch "$LUKS_CASE/prompted"
    printf '%s' "$LUKS_NEW"
    exit "$LUKS_INPUT_STATUS"
  fi
  printf '%s' "$LUKS_CONFIRMATION"
  exit "$LUKS_CONFIRM_STATUS"
  ;;
sudo)
  printf '%s\0' "$@" >"$LUKS_CASE/sudo-args"
  [[ ! ${new_password+x} ]] || printf 'new_password\n' >>"$LUKS_CASE/environment-leaks"
  [[ ! ${confirmation+x} ]] || printf 'confirmation\n' >>"$LUKS_CASE/environment-leaks"
  (( LUKS_SUDO_STATUS == 0 )) || exit "$LUKS_SUDO_STATUS"
  exec "$@"
  ;;
cryptsetup)
  printf '%s\0' "$@" >"$LUKS_CASE/cryptsetup-args"
  (( $# == 7 )) || exit 97
  [[ $1 == "luksChangeKey" && $2 == "--pbkdf" && $3 == "argon2id" &&
    $4 == "--iter-time" && $5 == "2000" && $6 == "$LUKS_EXPECTED_DRIVE" ]] || exit 97
  [[ -t 0 && -p $7 ]] || exit 97
  cat -- "$7" >"$LUKS_CASE/received-key"
  IFS= read -r -t 2 current || exit 97
  [[ $current == "current-test-password" ]] || exit 97
  exit "$LUKS_CRYPTSETUP_STATUS"
  ;;
esac

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin"
for stub in blkid monarch-drive-select gum sudo cryptsetup; do
  ln -s "$ROOT/test/monarch-drive-password-test.sh" "$test_dir/bin/$stub"
done
export ROOT PATH="$test_dir/bin:$PATH"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

reset_case() {
  export LUKS_CASE
  LUKS_CASE=$(mktemp -d "$test_dir/case.XXXXXX")
  export LUKS_DRIVES=/dev/test-luks LUKS_SELECTED=/dev/test-luks
  export LUKS_EXPECTED_DRIVE=/dev/test-luks LUKS_SELECT_STATUS=0
  export LUKS_NEW=replacement-test-password LUKS_CONFIRMATION=replacement-test-password
  export LUKS_INPUT_STATUS=0 LUKS_CONFIRM_STATUS=0 LUKS_SUDO_STATUS=0 LUKS_CRYPTSETUP_STATUS=0
}

run_case() {
  if new_password=seed confirmation=seed bash -c \
    'set -a; export SHELLOPTS; exec bash "$ROOT/bin/monarch-drive-password"' >"$LUKS_CASE/output" 2>&1; then
    status=0
  else
    status=$?
  fi
}

run_case_pty() {
  if printf 'current-test-password\n' |
    timeout 10s script -q -e -E never -c \
      'new_password=seed confirmation=seed bash -c '\''set -a; export SHELLOPTS; exec bash "$ROOT/bin/monarch-drive-password"'\''' \
      /dev/null >"$LUKS_CASE/output" 2>&1; then
    status=0
  else
    status=$?
  fi
  (( status != 124 )) || fail "password change hung"
}

assert_rejected() {
  (( status != 0 )) || fail "$1 returned success"
  [[ ! -e $LUKS_CASE/sudo-args ]] || fail "$1 reached sudo before validation"
}

reset_case
LUKS_NEW=''
LUKS_CONFIRMATION=''
run_case
assert_rejected "empty replacement"
grep -qF 'Password cannot be empty.' "$LUKS_CASE/output" || fail "empty replacement has no explanation"
[[ $(wc -l <"$LUKS_CASE/prompts") == 1 ]] || fail "empty replacement prompted for confirmation"

for confirmation in '' wrong-password '*'; do
  reset_case
  LUKS_CONFIRMATION=$confirmation
  run_case
  assert_rejected "mismatched confirmation"
  grep -qF 'Passwords do not match.' "$LUKS_CASE/output" || fail "mismatch has no explanation"
done

for prompt in LUKS_INPUT_STATUS LUKS_CONFIRM_STATUS; do
  for code in 1 130; do
    reset_case
    printf -v "$prompt" '%s' "$code"
    run_case
    assert_rejected "cancelled prompt"
    (( status == code )) || fail "prompt cancellation lost its exit status"
  done
done
printf 'ok - empty, mismatched and cancelled input never reaches sudo\n'

printf -v max_password '%*s' 512 ''
max_password=${max_password// /x}
for password in 'replacement-test-password' '   ' '  p@ss "quote" '\''quote %s $() `literal` \\ * [ab] café  ' "$max_password"; do
  reset_case
  LUKS_NEW=$password
  LUKS_CONFIRMATION=$password
  run_case_pty
  (( status == 0 )) || fail "valid replacement failed"
  printf '%s' "$password" | cmp -s - "$LUKS_CASE/received-key" || fail "replacement bytes changed"
  [[ $(wc -l <"$LUKS_CASE/prompts") == 2 ]] || fail "valid replacement was not confirmed"
  grep -qxF -- 'input --password --char-limit=512 --header New encryption password' "$LUKS_CASE/prompts" ||
    fail "new-password prompt changed its secure input contract"
  grep -qxF -- 'input --password --char-limit=512 --header Confirm new encryption password' "$LUKS_CASE/prompts" ||
    fail "confirmation prompt changed its secure input contract"
  if grep -qF -- "$password" "$LUKS_CASE/sudo-args" "$LUKS_CASE/cryptsetup-args"; then
    fail "replacement leaked into command arguments"
  fi
  [[ ! -e $LUKS_CASE/environment-leaks ]] || fail "replacement leaked into a child-process environment"
done
printf 'ok - confirmed passwords travel unchanged through a pipe while current-password input stays on the terminal\n'

reset_case
LUKS_SUDO_STATUS=23
run_case
(( status == 23 )) || fail "sudo failure was swallowed"

reset_case
LUKS_CRYPTSETUP_STATUS=23
run_case_pty
(( status == 23 )) || fail "cryptsetup failure was swallowed"
printf 'ok - sudo and cryptsetup failures propagate\n'

reset_case
LUKS_DRIVES=$'/dev/first-luks\n/dev/second-luks'
LUKS_SELECTED=/dev/second-luks
LUKS_EXPECTED_DRIVE=/dev/second-luks
run_case_pty
(( status == 0 )) || fail "selected drive was not changed"

reset_case
LUKS_DRIVES=$'/dev/first-luks\n/dev/second-luks'
LUKS_SELECTED=''
LUKS_SELECT_STATUS=1
run_case
(( status == 0 )) || fail "drive-selection cancellation changed status"
[[ ! -e $LUKS_CASE/prompts && ! -e $LUKS_CASE/sudo-args ]] || fail "cancelled selection reached password handling"

reset_case
LUKS_DRIVES=''
run_case
assert_rejected "no encrypted drives"
[[ ! -e $LUKS_CASE/prompts ]] || fail "no encrypted drives prompted for a password"
printf 'ok - drive discovery, selection and cancellation keep their existing behavior\n'
