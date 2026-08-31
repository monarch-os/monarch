#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"

for command in xdg-user-dirs-update xdg-settings xdg-mime; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
chmod +x "$mock_bin"/*

# Provisioning prepends $MONARCH_PATH/bin, which shadows a mock for anything
# Monarch ships, so the install suite is stubbed out at its path instead. The
# real one changes the live desktop through Noctalia and gsettings, then runs a
# global Node install.
mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" MONARCH_PATH="$ROOT" \
  MONARCH_INSTALL="$test_tmp/install" bash "$ROOT/bin/monarch-provision-user" --first-install >/dev/null ||
  fail "monarch-provision-user finishes"

for skill in diagnose-crash; do
  link="$test_tmp/home/.gemini/config/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "monarch-provision-user provisions the $skill skill for Antigravity"
done

pass "monarch-provision-user provisions Antigravity skills"

[[ $(<"$test_tmp/home/.local/state/monarch/schema") == 2 ]] ||
  fail "fresh installs record the current reconciliation schema"
pass "monarch-provision-user records the current reconciliation schema"
