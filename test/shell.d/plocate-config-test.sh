#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

drop_in="$ROOT/etc/systemd/system/plocate-updatedb.service.d/ac-only.conf"
grep -q '^ConditionACPower=true$' "$drop_in" ||
  fail "plocate updates are not restricted to AC power"
grep -q '^ExecStart=$' "$drop_in" || fail "plocate does not clear the packaged ExecStart"
grep -q '^ExecStart=/usr/bin/updatedb --prune-bind-mounts=no --add-prunepaths=/\.snapshots$' "$drop_in" ||
  fail "plocate service does not index subvolumes while pruning snapshots"
pass "the packaged plocate service owns Monarch's indexing policy"

[[ ! -e $ROOT/install/config/locate.sh ]] ||
  fail "the installer still mutates plocate's /etc/updatedb.conf"
! grep -ERq 'config/locate\.sh|/etc/updatedb\.conf' "$ROOT/install" ||
  fail "the install path still refers to the mutable plocate configuration"
pass "the installer leaves plocate's owned configuration untouched"

fake_bin="$test_tmp/bin"
log="$test_tmp/updatedb.log"
mkdir -p "$fake_bin"

cat >"$fake_bin/updatedb" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$UPDATEDB_LOG"
STUB
chmod +x "$fake_bin/updatedb"

PATH="$fake_bin:/usr/bin" UPDATEDB_LOG="$log" \
  bash "$ROOT/install/post-install/localdb.sh"
[[ $(<"$log") == "--prune-bind-mounts=no --add-prunepaths=/.snapshots" ]] ||
  fail "post-install updatedb does not share the packaged indexing policy" "$(<"$log")"
pass "post-install database creation shares the packaged indexing policy"

cat >"$fake_bin/yay" <<'STUB'
#!/bin/bash
case $1 in
  -Slqa) printf '%s\n' sample-package ;;
esac
STUB
cat >"$fake_bin/fzf" <<'STUB'
#!/bin/bash
cat
STUB
cat >"$fake_bin/monarch-sudo-keepalive" <<'STUB'
:
STUB
cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
[[ $1 == updatedb ]] || exit 64
shift
printf '%s\n' "$*" >>"$UPDATEDB_LOG"
STUB
cat >"$fake_bin/monarch-show-done" <<'STUB'
#!/bin/bash
:
STUB
chmod +x "$fake_bin/yay" "$fake_bin/fzf" "$fake_bin/sudo" \
  "$fake_bin/monarch-show-done"

: >"$log"
PATH="$fake_bin:/usr/bin" UPDATEDB_LOG="$log" \
  bash "$ROOT/bin/monarch-pkg-aur-install"
[[ $(<"$log") == "--prune-bind-mounts=no --add-prunepaths=/.snapshots" ]] ||
  fail "AUR installation updatedb does not share the packaged indexing policy" "$(<"$log")"
pass "AUR installation shares the packaged indexing policy"
