#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export MISE_DATA_DIR="$test_tmp/mise data"
export MONARCH_PATH="$ROOT"

[[ -f $ROOT/etc/mise/conf.d/monarch.toml ]] || fail "the package supplies mise defaults"
python3 - "$ROOT/etc/mise/conf.d/monarch.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
assert config["settings"]["upgrade"]["auto_prune"] is False
assert "tools" not in config, "Cursor must stay optional"
cursor = config["tool_alias"]["cursor-agent"]
assert "bin_path=bin" in cursor
assert "dist-package/cursor-agent" in cursor
PY
pass "packaged mise defaults match Quattro without enabling optional tools"

bundle="$MISE_DATA_DIR/installs/cursor-agent/2026.09.08-abcd"
mkdir -p "$bundle/dist-package"
printf '#!/bin/bash\nprintf cursor-ok\\n\n' >"$bundle/dist-package/cursor-agent"
printf '#!/bin/bash\nprintf bundled-node\\n\n' >"$bundle/dist-package/node"
chmod +x "$bundle/dist-package/"*
bash "$ROOT/install/reconcile/mise.sh"
[[ $(readlink "$bundle/bin/cursor-agent") == ../dist-package/cursor-agent ]] || fail "an existing bundle has no isolated launcher"
[[ ! -e $bundle/bin/node ]] || fail "the bundled Node leaks into the exposed directory"
inode=$(stat -c %i "$bundle/bin/cursor-agent")
bash "$ROOT/install/reconcile/mise.sh"
[[ $(stat -c %i "$bundle/bin/cursor-agent") == "$inode" ]] || fail "reconciliation replaces an already correct launcher"
pass "existing Cursor bundles gain an isolated launcher without reinstalling or moving their binaries"

rm "$bundle/bin/cursor-agent"
printf '%s\n' custom >"$bundle/bin/cursor-agent"
bash "$ROOT/install/reconcile/mise.sh"
[[ $(<"$bundle/bin/cursor-agent") == custom ]] || fail "reconciliation overwrites a customized launcher"

external="$test_tmp/external"
mkdir -p "$external"
rm "$bundle/bin/cursor-agent"
rmdir "$bundle/bin"
ln -s "$external" "$bundle/bin"
bash "$ROOT/install/reconcile/mise.sh"
[[ ! -e $external/cursor-agent ]] || fail "reconciliation follows a redirected bin directory"
pass "custom launchers and redirected bundle directories remain untouched"
