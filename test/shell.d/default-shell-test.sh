#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

usermod() { printf '%s\n' "$*" >>"$test_tmp/calls"; }

MONARCH_FIRST_INSTALL=1
MONARCH_INSTALL_USER=new-owner
source "$ROOT/install/config/default-shell.sh"
[[ $(<"$test_tmp/calls") == "-s /bin/zsh new-owner" ]] || fail "fresh install selects Zsh"
pass "fresh installation selects Zsh"

: >"$test_tmp/calls"
MONARCH_FIRST_INSTALL=0
source "$ROOT/install/config/default-shell.sh"
MONARCH_FIRST_INSTALL=1
MONARCH_INSTALL_USER=""
source "$ROOT/install/config/default-shell.sh"
unset MONARCH_FIRST_INSTALL MONARCH_INSTALL_USER
source "$ROOT/install/config/default-shell.sh"
[[ ! -s $test_tmp/calls ]] || fail "upgrade or deferred setup changes an existing shell"
pass "upgrades and account-free setup leave shells unchanged"

grep -qF 'config/default-shell.sh' "$ROOT/install/config/all.sh" || fail "shell setup is not wired"
# Inspect the real account-creation function without running its privileged writes.
create_user_source=$(sed -n '/^create_user() {/,/^}/p' "$ROOT/bin/monarch-provision-owner")
[[ $create_user_source == *'useradd -m -G "$(user_groups)" -s /bin/zsh'* ]] || fail "deferred account does not select Zsh"
[[ $create_user_source != *'usermod -s'* ]] || fail "retry replaces an existing shell"
pass "deferred provisioning selects Zsh only when creating an account"
