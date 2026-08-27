#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

remove="$ROOT/bin/monarch-remove-security-fido2"
test_tmp=$(mktemp -d)
authdir="$test_tmp/fido2"
remove_copy="$test_tmp/remove"
stub_bin="$test_tmp/bin"
mkdir "$stub_bin"
trap 'rm -rf "$test_tmp"' EXIT

[[ $(grep -Fxc 'authdir=/etc/fido2' "$remove") == 1 ]] || fail "removal has one fixed auth directory seam"
sed "s|^authdir=/etc/fido2$|authdir=$authdir|" "$remove" >"$remove_copy"

cat >"$stub_bin/grep" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$stub_bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
EOF
cat >"$stub_bin/sudo" <<'EOF'
#!/bin/bash
case $1 in
  rm) exec /usr/bin/rm "${@:2}" ;;
  sed) exit 0 ;;
  *) exit 97 ;;
esac
EOF
chmod +x "$stub_bin"/*

run_remove() {
  PATH="$stub_bin:$ROOT/bin:/usr/bin" bash "$remove_copy" >/dev/null
}

mkdir "$authdir"
printf credential >"$authdir/fido2"
run_remove
[[ ! -e $authdir ]] || fail "removal deletes the registration hierarchy"
pass "FIDO2 removal deletes its registration hierarchy"

mkdir "$test_tmp/elsewhere"
printf canary >"$test_tmp/elsewhere/canary"
ln -s "$test_tmp/elsewhere" "$authdir"
run_remove
[[ ! -L $authdir && -f $test_tmp/elsewhere/canary ]] || fail "removal followed an unsafe directory symlink"
pass "FIDO2 removal unlinks an unsafe directory symlink without following it"

ln -s "$test_tmp/missing" "$authdir"
run_remove
[[ ! -L $authdir ]] || fail "removal leaves a dangling directory symlink"
pass "FIDO2 removal clears a dangling directory symlink"
