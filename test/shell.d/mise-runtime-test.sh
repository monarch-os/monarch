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
assert "tool_alias" not in config, "system aliases mask user aliases in mise 2026.9.6"
PY
pass "packaged mise defaults preserve running versions without enabling optional tools"

cat >"$test_tmp/bin/mise" <<'STUB'
#!/bin/bash
case $1 in
  --version) printf '%s linux-x64\n' "${MISE_TEST_VERSION:-2026.9.6}" ;;
  config) printf '%s\n' "${MISE_TEST_CONFIGS:-[]}" ;;
  tool-alias) printf '%s\n' "$*" >>"$MISE_TEST_CALLS" ;;
  *) exit 98 ;;
esac
STUB
chmod +x "$test_tmp/bin/mise"
export MISE_TEST_CALLS="$test_tmp/calls"

for version in 2026.9.6 2026.10.1 2027.1.0; do
  MISE_TEST_VERSION=$version bash "$ROOT/bin/monarch-mise-ensure-cursor"
done
for version in 2026.8.14 2026.9.5 unknown 2026.9.6-beta.1; do
  if MISE_TEST_VERSION=$version bash "$ROOT/bin/monarch-mise-ensure-cursor" >"$test_tmp/out" 2>&1; then
    fail "an unqualified mise version is accepted: $version"
  fi
  grep -q 'monarch update' "$test_tmp/out" || fail "an unsupported mise version has no update guidance"
done
pass "Cursor requires a qualified mise registry version before any installation"

grep -q 'bin_path=bin' "$MISE_TEST_CALLS" || fail "Cursor defaults expose the whole bundle"
: >"$MISE_TEST_CALLS"
MISE_TEST_VERSION=2026.8.14 bash "$ROOT/bin/monarch-mise-ensure-cursor" --if-supported
[[ ! -s $MISE_TEST_CALLS ]] || fail "reconciliation configures unsupported optional tools"

for section in tool_alias alias; do
  printf '[%s]\ncursor-agent = "http:cursor-agent[bin_path=custom-bin]"\n' "$section" >"$test_tmp/custom.toml"
  export MISE_TEST_CONFIGS="[{\"path\":\"$test_tmp/custom.toml\"}]"
  bash "$ROOT/bin/monarch-mise-ensure-cursor"
  [[ ! -s $MISE_TEST_CALLS ]] || fail "Cursor defaults replace an existing $section"
done
mv "$test_tmp/custom.toml" "$test_tmp/custom-config"
MISE_GLOBAL_CONFIG_FILE="$test_tmp/custom-config" \
  MISE_TEST_CONFIGS="[{\"path\":\"$test_tmp/custom-config\"}]" \
  bash "$ROOT/bin/monarch-mise-ensure-cursor"
[[ ! -s $MISE_TEST_CALLS ]] || fail "an explicitly named config without a TOML extension is ignored"
printf 'invalid = [\n' >"$test_tmp/custom.toml"
if bash "$ROOT/bin/monarch-mise-ensure-cursor" >/dev/null 2>&1; then
  fail "an unreadable alias configuration is treated as absent"
fi
[[ ! -s $MISE_TEST_CALLS ]] || fail "an unreadable configuration is modified"
unset MISE_TEST_CONFIGS
pass "Cursor seeds an optional user-owned alias and preserves both alias formats"

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
