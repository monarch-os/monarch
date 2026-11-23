#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
export KEYRING_TEST_DIR="$test_tmp"
export PATH="$stub_bin:/usr/bin:/bin"
key=519BC3D5AEA652C94F89F0AAC13B3766D969CE82

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s' "$1" >>"$KEYRING_TEST_DIR/calls"
printf '\t%s' "${@:2}" >>"$KEYRING_TEST_DIR/calls"
printf '\n' >>"$KEYRING_TEST_DIR/calls"
step=
case "$*" in
  'pacman-key --list-keys 519BC3D5AEA652C94F89F0AAC13B3766D969CE82')
    count=$(cat "$KEYRING_TEST_DIR/list-count")
    echo "$((count + 1))" >"$KEYRING_TEST_DIR/list-count"
    if [[ $count == "0" && ${KEYRING_TEST_MISSING_KEY:-0} == "1" ]]; then
      exit 1
    fi
    step="list-$((count + 1))"
    ;;
  'pacman-key --recv-keys 519BC3D5AEA652C94F89F0AAC13B3766D969CE82 --keyserver keys.openpgp.org') step=recv ;;
  'pacman-key --lsign-key 519BC3D5AEA652C94F89F0AAC13B3766D969CE82') step=sign ;;
  'pacman -Sy') step=sync ;;
  'pacman -Sy --noconfirm archlinux-keyring'*) step=refresh ;;
  'pacman -Sy --noconfirm cachyos-keyring') step=cachy ;;
  *) echo "Unexpected sudo invocation: $*" >&2; exit 90 ;;
esac
if [[ ${KEYRING_TEST_FAIL:-} == "$step" ]]; then
  echo "error: injected $step failure" >&2
  exit 42
fi
if [[ $step == "refresh" ]]; then
  if [[ ${KEYRING_TEST_WARN:-0} == "1" ]]; then
    echo 'warning: archlinux-keyring-20260909-1 is up to date -- reinstalling' >&2
    echo 'warning: monarch-keyring-20251028-1 is up to date -- reinstalling' >&2
    echo 'warning: other-keyring-1-1 is up to date -- reinstalling' >&2
    echo 'warning: monarch-keyring-20251028-1 is up to date -- skipping' >&2
    echo 'warning: monarch-keyring: unexpected signature warning' >&2
    echo 'error: diagnostic must survive filtering' >&2
  fi
  for package in "${@:4}"; do
    case "$package" in
      archlinux-keyring) ;;
      monarch-keyring)
        cat "$KEYRING_TEST_DIR/repository-version" >"$KEYRING_TEST_DIR/installed-version"
        cp "$KEYRING_TEST_DIR/installed-version" "$KEYRING_TEST_DIR/monarch-populated"
        ;;
      *) echo "Unexpected keyring: $package" >&2; exit 91 ;;
    esac
  done
fi
SH

cat >"$stub_bin/monarch-pkg-missing" <<'SH'
#!/bin/bash
[[ $* == "monarch-keyring" ]] || exit 90
[[ ${KEYRING_TEST_MISSING_PACKAGE:-0} == "1" ]]
SH

cat >"$stub_bin/monarch-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add\t%s\n' "$*" >>"$KEYRING_TEST_DIR/calls"
[[ $* == "monarch-keyring" ]] || exit 90
if [[ ${KEYRING_TEST_FAIL:-} == "install" ]]; then
  echo 'error: injected install failure' >&2
  exit 42
fi
SH

cat >"$stub_bin/monarch-update-pacman" <<'SH'
#!/bin/bash
printf 'main\t%s\n' "$*" >>"$KEYRING_TEST_DIR/calls"
[[ $* == "-Syyu --noconfirm" ]] || exit 90
if [[ ! -f $KEYRING_TEST_DIR/monarch-populated ]]; then
  echo 'error: main transaction cannot verify the newly signed package' >&2
  exit 43
fi
SH
chmod +x "$stub_bin/"*

run_keyring() {
  : >"$test_tmp/calls"
  echo 0 >"$test_tmp/list-count"
  echo "${KEYRING_TEST_INSTALLED_VERSION:-1}" >"$test_tmp/installed-version"
  echo 2 >"$test_tmp/repository-version"
  rm -f "$test_tmp/monarch-populated"
  # Drain stderr to EOF: the warning filter can outlive the command itself.
  "$ROOT/bin/monarch-update-keyring" 2>&1 | cat
}

assert_call() {
  grep -Fxq -- "$1" "$test_tmp/calls" || fail "$2" "$(cat "$test_tmp/calls")"
}

assert_absent() {
  if grep -Fq -- "$1" "$test_tmp/calls"; then
    fail "$2" "$(cat "$test_tmp/calls")"
  fi
}

for state in newer current; do
  installed=1
  [[ $state != "current" ]] || installed=2
  KEYRING_TEST_INSTALLED_VERSION=$installed run_keyring >"$test_tmp/$state.out" || fail "refresh succeeds with an installed $state keyring" "$(cat "$test_tmp/$state.out")"
  assert_call $'pacman\t-Sy\t--noconfirm\tarchlinux-keyring\tmonarch-keyring' "refresh includes Monarch even with its package and historical key present"
  assert_call $'pacman\t-Sy\t--noconfirm\tcachyos-keyring' "refresh preserves CachyOS"
  assert_absent 'recv-keys' "installed key is not bootstrapped again"
  assert_absent 'pkg-add' "installed package does not use bootstrap"
  grep -Fxq 'Keys are correct' "$test_tmp/$state.out" || fail "successful refresh is verified"
  [[ -f $test_tmp/monarch-populated ]] || fail "current and newer packages both repopulate Monarch keys"
  [[ $(cat "$test_tmp/installed-version") == "2" && $(cat "$test_tmp/monarch-populated") == "2" ]] || fail "repository keyring version is installed and populated"
  "$ROOT/bin/monarch-update-system-pkgs" >"$test_tmp/main.out" 2>&1 || fail "main transaction can verify newly signed packages" "$(cat "$test_tmp/main.out")"
  python3 - "$test_tmp/calls" <<'PY'
import pathlib, sys
calls = pathlib.Path(sys.argv[1]).read_text().splitlines()
refresh = calls.index('pacman\t-Sy\t--noconfirm\tarchlinux-keyring\tmonarch-keyring')
cachy = calls.index('pacman\t-Sy\t--noconfirm\tcachyos-keyring')
assert refresh < cachy < len(calls) - 2
assert calls[-2].startswith('pacman-key\t--list-keys\t')
assert calls[-1] == 'main\t-Syyu --noconfirm'
PY
  pass "$state Monarch keyring refreshes and repopulates before the main package transaction"
done

for missing in package key; do
  if [[ $missing == "package" ]]; then
    KEYRING_TEST_MISSING_PACKAGE=1 run_keyring >"$test_tmp/bootstrap.out"
  else
    KEYRING_TEST_MISSING_KEY=1 run_keyring >"$test_tmp/bootstrap.out"
  fi
  python3 - "$test_tmp/calls" "$key" <<'PY'
import pathlib, sys
calls = pathlib.Path(sys.argv[1]).read_text().splitlines()
key = sys.argv[2]
bootstrap = [f'pacman-key\t--recv-keys\t{key}\t--keyserver\tkeys.openpgp.org',
             f'pacman-key\t--lsign-key\t{key}', 'pacman\t-Sy', 'pkg-add\tmonarch-keyring',
             f'pacman-key\t--list-keys\t{key}',
             'pacman\t-Sy\t--noconfirm\tarchlinux-keyring\tmonarch-keyring',
             'pacman\t-Sy\t--noconfirm\tcachyos-keyring', f'pacman-key\t--list-keys\t{key}']
assert calls == bootstrap or calls == [f'pacman-key\t--list-keys\t{key}'] + bootstrap, calls
PY
  grep -Fxq 'Keys are correct' "$test_tmp/bootstrap.out" || fail "bootstrap verifies success"
  pass "missing $missing preserves the Monarch fingerprint, local signing and bootstrap order"
done

for scenario in recv sign sync install bootstrap-verify refresh cachy final-verify; do
  missing=0
  step=$scenario
  forbidden=
  case "$scenario" in
    recv) missing=1; forbidden=lsign-key ;;
    sign) missing=1; forbidden=$'pacman\t-Sy' ;;
    sync) missing=1; forbidden=pkg-add ;;
    install) missing=1; forbidden=archlinux-keyring ;;
    bootstrap-verify) missing=1; step=list-1; forbidden=archlinux-keyring ;;
    refresh) forbidden=cachyos-keyring ;;
    cachy) forbidden=$'main\t' ;;
    final-verify) step=list-2; forbidden=$'main\t' ;;
  esac
  status=0
  KEYRING_TEST_MISSING_PACKAGE=$missing KEYRING_TEST_FAIL=$step run_keyring >"$test_tmp/fail.out" || status=$?
  [[ $status == "42" ]] || fail "$scenario propagates failure status" "status=$status $(cat "$test_tmp/fail.out")"
  if grep -Fq 'Keys are correct' "$test_tmp/fail.out"; then
    fail "$scenario never reports false success" "$(cat "$test_tmp/fail.out")"
  fi
  grep -Fq "error: injected $step failure" "$test_tmp/fail.out" || fail "$scenario retains actionable diagnostics" "$(cat "$test_tmp/fail.out")"
  assert_absent "$forbidden" "$scenario stops before subsequent work"
  pass "$scenario fails closed, preserves diagnostics and never reports success"
done

KEYRING_TEST_WARN=1 run_keyring >"$test_tmp/warnings.out"
for package in archlinux-keyring monarch-keyring; do
  if grep -Eq "^warning: $package-[^ ]+ is up to date -- reinstalling$" "$test_tmp/warnings.out"; then
    fail "only benign reinstall notices are filtered" "$(cat "$test_tmp/warnings.out")"
  fi
done
for diagnostic in \
  'warning: other-keyring-1-1 is up to date -- reinstalling' \
  'warning: monarch-keyring-20251028-1 is up to date -- skipping' \
  'warning: monarch-keyring: unexpected signature warning' \
  'error: diagnostic must survive filtering'; do
  grep -Fxq "$diagnostic" "$test_tmp/warnings.out" || fail "unrelated diagnostic survives: $diagnostic" "$(cat "$test_tmp/warnings.out")"
done
pass "warning filter suppresses only Arch and Monarch benign reinstall notices"
