#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

packages="$ROOT/install/monarch-base.packages"
pacman_setup="$ROOT/install/post-install/pacman.sh"

for keyring in archlinux-keyring cachyos-keyring monarch-keyring; do
  grep -Fxq "$keyring" "$packages" ||
    fail "target package list installs $keyring"
done
pass "target package list installs every configured repository keyring"

grep -Eq '^pacman-key --populate archlinux cachyos monarch$' "$pacman_setup" ||
  fail "target setup populates every configured repository keyring"
pass "target setup populates every configured repository keyring"
