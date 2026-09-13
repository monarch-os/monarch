#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"
export MISE_TEST_LOG="$test_tmp/mise-calls"

cat >"$test_tmp/bin/mise" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
STUB
cat >"$test_tmp/bin/monarch-mise-install" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$test_tmp/bin/"*

[[ -f $ROOT/etc/mise/conf.d/monarch.toml ]] || fail "the package supplies mise defaults"
python3 - "$ROOT/etc/mise/conf.d/monarch.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
assert "tools" not in config, "Cursor must stay optional"
assert "settings" not in config, "user settings do not belong in system defaults"
cursor = config["tool_alias"]["cursor-agent"]
assert "bin_path=bin" in cursor
assert "dist-package/cursor-agent" in cursor
PY
pass "packaged mise defaults match Quattro without enabling optional tools"

source "$ROOT/install/user/mise.sh"
[[ $(<"$MISE_TEST_LOG") == "settings set upgrade.auto_prune false" ]] || fail "install does not persist the mise setting"

: >"$MISE_TEST_LOG"
bash "$ROOT/install/reconcile/mise.sh"
[[ $(<"$MISE_TEST_LOG") == "settings set upgrade.auto_prune false" ]] || fail "reconcile does not persist the mise setting"
pass "install and reconcile disable mise auto-pruning in the user settings"
