#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

if ((EUID == 0)); then
  # Root reconcilers ignore test overrides; exercise the fixture unprivileged.
  mkdir -p "$test_tmp/checkout/install/reconcile" "$test_tmp/checkout/test/shell.d"
  cp "$ROOT/install/reconcile/"{package-permissions,system}.sh "$test_tmp/checkout/install/reconcile/"
  cp "$SHELL_TEST_DIR/"{base,package-permissions}-test.sh "$test_tmp/checkout/test/shell.d/"
  chown -R 65534:65534 "$test_tmp"
  setpriv --reuid 65534 --regid 65534 --clear-groups \
    bash "$test_tmp/checkout/test/shell.d/package-permissions-test.sh"
  exit 0
fi

mkdir -p "$test_tmp/etc/NetworkManager/conf.d" "$test_tmp/etc/docker" \
  "$test_tmp/usr/share/monarch/config" "$test_tmp/outside" "$test_tmp/etc/private"
printf '%s\n' custom >"$test_tmp/etc/docker/daemon.json"
printf '%s\n' executable >"$test_tmp/usr/share/monarch/config/command"
touch "$test_tmp/outside/untouched" "$test_tmp/etc/private/config"
touch "$test_tmp/etc/NetworkManager/unpackaged"
chmod 0777 "$test_tmp/etc/NetworkManager" "$test_tmp/etc/NetworkManager/conf.d" \
  "$test_tmp/usr/share/monarch/config/command" "$test_tmp/outside/untouched"
chmod 0666 "$test_tmp/etc/docker/daemon.json"
chmod 0666 "$test_tmp/etc/NetworkManager/unpackaged"
chmod 0700 "$test_tmp/etc/private"
chmod 0660 "$test_tmp/etc/private/config"
ln -s "$test_tmp/outside" "$test_tmp/etc/linked"
ln -s "$test_tmp/outside/untouched" "$test_tmp/etc/symlink"
ln "$test_tmp/outside/untouched" "$test_tmp/etc/hardlink"
printf '%s\n' /etc/NetworkManager/ /etc/NetworkManager/conf.d/ \
  /etc/docker/daemon.json /usr/share/monarch/config/command /etc/private/ \
  /etc/private/config /etc/linked/ /etc/linked/untouched /etc/symlink /etc/hardlink /etc/missing \
  /etc/../outside/untouched \
  >"$test_tmp/paths"
export MONARCH_PACKAGE_PERMISSIONS_TEST_ROOT="$test_tmp"
export MONARCH_PACKAGE_PERMISSIONS_TEST_PATHS="$test_tmp/paths"

for run in 1 2; do
  bash "$ROOT/install/reconcile/package-permissions.sh"
  [[ $(stat -c %a "$test_tmp/etc/NetworkManager") == "755" ]]
  [[ $(stat -c %a "$test_tmp/etc/NetworkManager/conf.d") == "755" ]]
  [[ $(stat -c %a "$test_tmp/etc/docker/daemon.json") == "644" ]]
  [[ $(stat -c %a "$test_tmp/usr/share/monarch/config/command") == "755" ]]
  [[ $(stat -c %a "$test_tmp/outside/untouched") == "777" ]]
  [[ $(stat -c %a "$test_tmp/etc/private") == "700" ]]
  [[ $(stat -c %a "$test_tmp/etc/private/config") == "660" ]]
  [[ $(stat -c %a "$test_tmp/etc/NetworkManager/unpackaged") == "666" ]]
  [[ $(<"$test_tmp/etc/docker/daemon.json") == "custom" ]]
done
pass "packaged permissions repair is scoped, idempotent and preserves custom content and modes"

grep -qF 'sudo bash /usr/share/monarch/install/reconcile/package-permissions.sh' \
  "$ROOT/install/reconcile/system.sh" || fail "system reconciliation omits packaged permissions repair"
pass "every supported schema repairs contaminated package permissions"
