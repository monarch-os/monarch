#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
MONARCH_FACTORY_RESET_LIB_ONLY=true source "$ROOT/bin/monarch-system-factory-reset"
trap 'rm -rf "$test_tmp"' EXIT
LOG_FILE="$test_tmp/reset.log"
CALL_LOG="$test_tmp/calls"

userdel() {
  [[ $1 == --root && $2 == "$test_tmp/"* ]] || return 99
  printf 'userdel %s\n' "$3" >>"$CALL_LOG"
  [[ ${ACCOUNT_FAIL:-} != userdel ]] || return 1
  cp "$2/etc/passwd" "$2/etc/passwd-"
  cp "$2/etc/shadow" "$2/etc/shadow-"
  sed -i "/^$3:/d" "$2/etc/passwd" "$2/etc/shadow"
}

usermod() {
  [[ $1 == --root && $2 == "$test_tmp/"* && $3 == --password && $4 == '!' && $5 == root ]] || return 99
  printf '%s\n' usermod >>"$CALL_LOG"
  [[ ${ACCOUNT_FAIL:-} != usermod ]] || return 1
  cp "$2/etc/shadow" "$2/etc/shadow-"
  sed -i 's/^root:[^:]*:/root:!:/' "$2/etc/shadow"
}

btrfs() { printf '%s\n' "$*" >>"$CALL_LOG"; }
retire_factory_privilege_grants() { :; }
retire_factory_printer_discovery() { :; }
stage_current_apple_display_access() { :; }
gum() { :; }

make_root() {
  mkdir -p "$1/etc/ssh" "$1/etc/NetworkManager/system-connections" \
    "$1/home/owner" "$1/var/lib/sddm" "$1/etc/sddm.conf.d"
  printf '%s\n' 'root:x:0:0::/root:/bin/bash' 'service:x:900:900::/:/usr/bin/nologin' \
    'owner:x:1000:1000::/home/owner:/bin/bash' 'lastowner:x:60000:60000::/home/lastowner:/bin/bash' >"$1/etc/passwd"
  printf '%s\n' 'root:OLD_ROOT_HASH:0::::::' 'service:!:0::::::' 'owner:OLD_OWNER_HASH:0::::::' \
    'lastowner:LAST_OWNER_HASH:0::::::' >"$1/etc/shadow"
  mkdir -p "$1/home/lastowner"
  for file in shadow- gshadow- passwd- group- subuid- subgid-; do
    printf '%s\n' OLD_BACKUP_HASH >"$1/etc/$file"
  done
}

for name in next factory; do
  root="$test_tmp/$name"
  make_root "$root"
  scrub_factory_accounts "$root"
  grep -Fqx 'root:!:0::::::' "$root/etc/shadow" || fail "factory root retains the old root hash"
  grep -Fq 'service:' "$root/etc/passwd" || fail "factory scrub removes service accounts"
  ! grep -q 'owner:' "$root/etc/passwd" "$root/etc/shadow" || fail "factory scrub retains owner credentials"
  [[ ! -e $root/home/owner && ! -e $root/home/lastowner ]] || fail "factory scrub retains a user's home at a UID boundary"
  ! find "$root/etc" -maxdepth 1 -name '*-' -print -quit | grep -q . || fail "factory scrub retains account backups"
  scrub_factory_accounts "$root"
done
pass "both reset roots discard owner and root hashes including account-tool backups"

for failure in userdel usermod; do
  root="$test_tmp/failure-$failure"
  make_root "$root"
  : >"$CALL_LOG"
  if ACCOUNT_FAIL="$failure" scrub_factory_accounts "$root"; then
    fail "factory scrub ignores $failure failure"
  fi
  if (ACCOUNT_FAIL="$failure" sanitize_factory_baseline "$root"); then
    fail "factory baseline reports success after failed credential scrub"
  fi
  [[ $(tail -1 "$CALL_LOG") == "property set -ts $root ro true" ]] ||
    fail "failed factory baseline scrub leaves it writable"
done
pass "account cleanup failures stop reset and restore the baseline read-only flag"

grep -Fq 'scrub_factory_accounts "$next" ||' "$ROOT/bin/monarch-system-factory-reset" ||
  fail "the staged reset root bypasses account scrubbing"
