#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
authdir="$test_tmp/fido2"
authfile="$authdir/fido2"
pamdir="$test_tmp/pam.d"
setup_copy="$test_tmp/setup"
mkdir -p "$stub_bin" "$pamdir"
trap 'rm -rf "$test_tmp"' EXIT

setup="$ROOT/bin/monarch-setup-security-fido2"
[[ $(grep -Fxc 'authdir=/etc/fido2' "$setup") == 1 ]] || fail "setup has one fixed auth directory seam"
[[ $(grep -Fxc 'authfile=/etc/fido2/fido2' "$setup") == 1 ]] || fail "setup has one fixed authfile seam"
sed -e "s|^authdir=/etc/fido2$|authdir=$authdir|" \
  -e "s|^authfile=/etc/fido2/fido2$|authfile=$authfile|" \
  -e "s|/etc/pam.d|$pamdir|g" "$setup" >"$setup_copy"

cat >"$stub_bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
EOF
cat >"$stub_bin/fido2-token" <<'EOF'
#!/bin/bash
echo token
EOF
cat >"$stub_bin/grep" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$stub_bin/pamu2fcfg" <<'EOF'
#!/bin/bash
printf 'tester:credential\n'
[[ ${FAIL_PAMU:-0} == 0 ]]
EOF
cat >"$stub_bin/sudo" <<'EOF'
#!/bin/bash
set -e
printf '%s\n' "$*" >>"$SUDO_LOG"
case $1 in
  install) exec /usr/bin/install -d -m 755 "${@: -1}" ;;
  mktemp|chmod|mv|rm) exec "/usr/bin/$1" "${@:2}" ;;
  tee) exec /usr/bin/tee "$2" ;;
  sed|echo) exit 0 ;;
  *) exit 97 ;;
esac
EOF
chmod +x "$stub_bin"/*

run_setup() {
  SUDO_LOG="$test_tmp/sudo.log" PATH="$stub_bin:$ROOT/bin:/usr/bin" \
    bash "$setup_copy" </dev/null >/dev/null
}

mkdir "$authdir"
ln -s /dev/null "$authfile"
run_setup 2>/dev/null && fail "setup refuses a symlinked authfile"
[[ -L $authfile ]] || fail "setup leaves a symlinked authfile untouched"
pass "FIDO2 setup refuses a symlinked authfile"

rm -rf "$authdir"
mkdir "$test_tmp/elsewhere"
ln -s "$test_tmp/elsewhere" "$authdir"
run_setup 2>/dev/null && fail "setup refuses a symlinked auth directory"
[[ ! -e $test_tmp/elsewhere/fido2 ]] || fail "setup wrote through a symlinked auth directory"
pass "FIDO2 setup refuses a symlinked auth directory"

rm -rf "$authdir"
: >"$test_tmp/sudo.log"
run_setup
[[ -f $authfile && $(<"$authfile") == "tester:credential" ]] || fail "setup publishes the generated credential"
[[ $(stat -c %a "$authfile") == 644 ]] || fail "setup publishes mode 644"
grep -Fq "mktemp $authfile.new.XXXXXX" "$test_tmp/sudo.log" || fail "root creates a unique sibling stage"
grep -Fq "mv -Tf " "$test_tmp/sudo.log" || fail "setup publishes with an atomic rename"
[[ -z $(find "$authdir" -name 'fido2.new.*' -print -quit) ]] || fail "successful setup leaves no stage"
pass "FIDO2 setup publishes from a root-created sibling atomically"

rm -rf "$authdir"
: >"$test_tmp/sudo.log"
FAIL_PAMU=1 run_setup 2>/dev/null && fail "setup propagates credential generation failure"
[[ ! -e $authfile ]] || fail "failed setup publishes no credential"
[[ -z $(find "$authdir" -name 'fido2.new.*' -print -quit) ]] || fail "failed setup cleans its stage"
grep -Fq 'rm -f -- ' "$test_tmp/sudo.log" || fail "failed setup removes its exact stage"
pass "FIDO2 setup cleans its privileged stage on failure"
