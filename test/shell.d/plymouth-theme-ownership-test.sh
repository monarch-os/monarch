#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

theme_dir="$test_tmp/monarch"
mkdir -p "$test_tmp/bin" "$theme_dir"
chmod 0700 "$theme_dir"
cat >"$test_tmp/bin/chown" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CHOWN_LOG"
EOF
chmod +x "$test_tmp/bin/chown"

export PATH="$test_tmp/bin:/usr/bin"
export TEST_CHOWN_LOG="$test_tmp/chown.log"
export MONARCH_PLYMOUTH_OWNERSHIP_TEST_DIR="$theme_dir"

bash "$ROOT/install/reconcile/plymouth-theme-ownership.sh"
grep -qx "root:root $theme_dir" "$TEST_CHOWN_LOG"
[[ $(stat -c '%a' "$theme_dir") == "755" ]]
pass "reconciliation restores the packaged Plymouth directory metadata"

mv "$theme_dir" "$theme_dir.real"
ln -s "$theme_dir.real" "$theme_dir"
if bash "$ROOT/install/reconcile/plymouth-theme-ownership.sh" >/dev/null 2>&1; then
  fail "Plymouth ownership repair followed a symlinked directory"
fi
pass "Plymouth ownership repair rejects symlink targets"

grep -qF 'sudo bash /usr/share/monarch/install/reconcile/plymouth-theme-ownership.sh' \
  "$ROOT/install/reconcile/system.sh" ||
  fail "current-schema reconciliation does not repair the Plymouth directory"
pass "every supported schema runs the Plymouth ownership repair"
