#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

agent_reconciler="$ROOT/install/reconcile/schema/1-to-2/agents.sh"
system_reconciler="$ROOT/install/reconcile/schema/1-to-2/system-after-user.sh"
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/mise" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_MISE_CALLS"
EOF
cat >"$stub_bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_DROP_CALLS"
exit "${TEST_DROP_STATUS:-0}"
EOF
chmod +x "$stub_bin/mise" "$stub_bin/monarch-pkg-drop"

export MONARCH_PATH="$ROOT"
export PATH="$stub_bin:$ROOT/bin:/usr/bin"
export TEST_MISE_CALLS="$test_tmp/mise-calls"
export TEST_DROP_CALLS="$test_tmp/drop-calls"

write_direct_wrapper() {
  local file="$1" package="$2"

  printf '#!/bin/bash\nexec npx --yes %s "$@"\n' "$package" >"$file"
  chmod +x "$file"
}

write_mise_exec_wrapper() {
  local file="$1" package="$2"

  printf '#!/bin/bash\nexec mise exec node@latest -- npx --yes %s "$@"\n' "$package" >"$file"
  chmod +x "$file"
}

write_resolver_wrapper() {
  local file="$1" package="$2" command="$3"

  cat >"$file" <<EOF
#!/bin/bash
package="$package"
command="$command"

if ! node_root="\$(mise where node@latest 2>/dev/null)"; then
  mise use -g node@latest >/dev/null
  node_root="\$(mise where node@latest)"
fi

node_bin="\$node_root/bin/node"
npx_bin="\$node_root/bin/npx"

ensure_bin_runtime() {
  local bin_path=\$1
  local shebang

  IFS= read -r shebang < "\$bin_path"

  if [[ \$shebang == "#!"*"/bun"* || \$shebang == "#!"*"/env bun"* ]]; then
    if monarch-cmd-missing bun; then
      echo "Installing bun runtime for \$package..."
      monarch-pkg-add bun
      hash -r
    fi
  fi
}

exec_package_bin() {
  local package_bin_path=\$1
  shift

  if [[ -n \$package_bin_path ]]; then
    ensure_bin_runtime "\$package_bin_path"
    PATH="\$node_root/bin:\$PATH" exec "\$package_bin_path" "\$@"
  fi
}

# Resolve the package bin inside npx, then run it with node@latest available for node shebangs.
# Some wrappers are aliases, e.g. playwright-cli wraps the playwright bin.
"\$node_bin" "\$npx_bin" --yes --prefer-online --package "\$package" -- true

package_bin_path=\$("\$node_bin" "\$npx_bin" --yes --package "\$package" -- which "\$package" 2>/dev/null)
exec_package_bin "\$package_bin_path" "\$@"

# Scoped packages like @openai/codex expose an unscoped bin like codex.
package_bin_path=\$("\$node_bin" "\$npx_bin" --yes --package "\$package" -- which "\$command" 2>/dev/null)
exec_package_bin "\$package_bin_path" "\$@"

echo "Could not resolve npm bin for \$package / \$command" >&2
exit 127
EOF
  chmod +x "$file"
}

assert_hash() {
  local file="$1" expected="$2" actual

  actual=$(sha256sum "$file")
  actual=${actual%% *}
  [[ $actual == $expected ]] || fail "fixture hash for ${file##*/} is canonical" "$actual"
}

assert_mise_wrapper() {
  local home="$1" command="$2" package="$3" bin="${4:-$2}"
  local file="$home/.local/bin/$command"

  [[ -x $file ]] || fail "$command was not installed as an executable mise wrapper"
  grep -Fqx "mise use -g --quiet $package || exit 1" "$file" ||
    fail "$command does not select its V5 mise package"
  grep -Fqx "exec mise x $package -- $bin \"\$@\"" "$file" ||
    fail "$command does not launch its V5 binary"
}

assert_v5_catalog() {
  local home="$1"

  assert_mise_wrapper "$home" codex codex
  assert_mise_wrapper "$home" claude claude
  assert_mise_wrapper "$home" crush crush
  assert_mise_wrapper "$home" agy antigravity-cli
  assert_mise_wrapper "$home" copilot copilot
  assert_mise_wrapper "$home" opencode opencode
  assert_mise_wrapper "$home" pi pi
  assert_mise_wrapper "$home" omp github:can1357/oh-my-pi
  assert_mise_wrapper "$home" grok npm:@xai-official/grok
  assert_mise_wrapper "$home" ori github:OpenRouterLabs/ori-releases
  assert_mise_wrapper "$home" playwright-cli npm:playwright playwright
  assert_mise_wrapper "$home" ghui npm:@kitlangton/ghui
  [[ ! -e $home/.local/bin/gemini ]] || fail "the retired Gemini wrapper remains"
}

prepare_home() {
  local home="$1" default_agent="$2"

  mkdir -p "$home/.local/bin" "$home/.config/monarch/defaults"
  printf %s "$default_agent" >"$home/.config/monarch/defaults/agent"
}

run_reconciler() {
  HOME="$1" bash "$agent_reconciler"
  HOME="$1" bash "$system_reconciler"
}

direct_home="$test_tmp/direct"
prepare_home "$direct_home" gemini
while IFS='|' read -r command package expected; do
  write_direct_wrapper "$direct_home/.local/bin/$command" "$package"
  assert_hash "$direct_home/.local/bin/$command" "$expected"
done <<'EOF'
codex|@openai/codex|83e2049bd3aceb9315baef891113084cd58da90f79f245c2905bfb9b473f85a9
gemini|@google/gemini-cli|12cf78e12f1741b48b2be025801e74bdf009310025cbb8d0916c73be47382f12
copilot|@github/copilot|7b056fa754f1481476be29a00555c0a46a2fc7628ac4d66a51d08a727fb9c14d
opencode|opencode-ai|64242a7b1f18c80449b1dedf1f9014456e6ba948880555797bcb6fd039213f32
playwright-cli|playwright|a6f3a1a44bcaae6c6dffaf8d667db8c7d52219154b19d897e915d1f39da8b4f3
pi|@mariozechner/pi-coding-agent|3a575d8912a71afdc8ee6083db2025f2a5e7a11654a9257f4adfc8f36b425548
EOF
run_reconciler "$direct_home"
assert_v5_catalog "$direct_home"
[[ $(<"$direct_home/.config/monarch/defaults/agent") == "agy" ]] ||
  fail "the direct-wrapper generation did not migrate Gemini to Antigravity"
pass "the original V4 npx wrappers migrate to the V5 mise catalog"

mise_exec_home="$test_tmp/mise-exec"
prepare_home "$mise_exec_home" gemini-cli
while IFS='|' read -r command package expected; do
  write_mise_exec_wrapper "$mise_exec_home/.local/bin/$command" "$package"
  assert_hash "$mise_exec_home/.local/bin/$command" "$expected"
done <<'EOF'
codex|@openai/codex|aa0e447be861b173f03ea5cdf4d74c0cb266f078937a9667caf2f10baa1489ac
gemini|@google/gemini-cli|efadd401e4d3ad26c8e8619ee3bd3e783691f3edc3bf562fd89bdcd3cc29f1bc
copilot|@github/copilot|dbe263ab39a5dd802c8fb00c932d25edc0b03a28ef73a1af58cfa6d6e3d54d92
opencode|opencode-ai|5a8ce75fd238f95d5e2cc85d5b47b2da79894dfac6e268e592ed8038f13aa05d
playwright-cli|playwright|7429554aadd460e6db7d50c2da12c01c7cac01f5b9ed3d478c370ac60c44254e
pi|@mariozechner/pi-coding-agent|9aded70a3b69a309669133ff12723d327a9ec49d51ea15abe5dffe0c9dbe5267
EOF
run_reconciler "$mise_exec_home"
assert_v5_catalog "$mise_exec_home"
[[ $(<"$mise_exec_home/.config/monarch/defaults/agent") == "agy" ]] ||
  fail "the mise-exec generation did not migrate Gemini to Antigravity"
pass "the intermediate V4 wrappers migrate to the V5 mise catalog"

resolver_home="$test_tmp/resolver"
prepare_home "$resolver_home" gemini
while IFS='|' read -r command package expected; do
  write_resolver_wrapper "$resolver_home/.local/bin/$command" "$package" "$command"
  assert_hash "$resolver_home/.local/bin/$command" "$expected"
done <<'EOF'
codex|@openai/codex|284bad8b2bd46123defad1fd3d4b4d3f6aec70b74369add52fd2707a38f02113
gemini|@google/gemini-cli|a7ef601d57c20315c297127638bb2a5d7946ea1c7e599f487428e385fcb6776b
copilot|@github/copilot|a03be1e0c7f11439f2223e50680e3463a5148eb9ea210eb0842b6d2d000e63a6
opencode|opencode-ai|44623bd0a45e49f448ec1006feacc7dedcc74b5f85e7fa9fd1def5aff87c11a5
playwright-cli|playwright|1b0768506b5921289a844b68ddbe515527a6ab0682c76868de0467ae202a4b3d
pi|@mariozechner/pi-coding-agent|6be1d2199d82979aa67278fe5513f2b0f485a727acf5ac14bc1ef23355268024
ghui|@kitlangton/ghui|ea1ec68d3c2c71db266f3d3f97df2d79ee763d6540175f46fb54a320c582abb4
crush|@charmland/crush|b6e9246618be552c8841d7ab3aed18438abb9870dfd521d375a236ccd8358bce
grok|@xai-official/grok|5578cdc2da3149e93ad2bd507af2ea987098316f642b20a63029b65deee99b28
EOF
run_reconciler "$resolver_home"
assert_v5_catalog "$resolver_home"
pass "the final V4 resolver wrappers migrate to the V5 mise catalog"

pi_home="$test_tmp/pi-provider"
prepare_home "$pi_home" claude
write_resolver_wrapper "$pi_home/.local/bin/pi" @earendil-works/pi-coding-agent pi
assert_hash "$pi_home/.local/bin/pi" \
  60c302de0b45e4343afe253666532ba765f17840183dcd822402870b95cdb42b
run_reconciler "$pi_home"
assert_v5_catalog "$pi_home"
[[ $(<"$pi_home/.config/monarch/defaults/agent") == "claude" ]] ||
  fail "an unrelated default agent was changed"
pass "the renamed V4 Pi package migrates without changing another default"

empty_home="$test_tmp/empty"
mkdir -p "$empty_home"
run_reconciler "$empty_home"
assert_v5_catalog "$empty_home"
[[ ! -e $empty_home/.config/monarch/defaults/agent ]] ||
  fail "reconciliation selected a default agent for the user"
pass "an installation without an agent choice gains wrappers but no default"

symlink_home="$test_tmp/symlink-default"
mkdir -p "$symlink_home/.config/monarch/defaults" "$symlink_home/.local/bin" \
  "$symlink_home/preferences"
printf '%s\n' gemini >"$symlink_home/preferences/agent"
ln -s "$symlink_home/preferences/agent" "$symlink_home/.config/monarch/defaults/agent"
write_direct_wrapper "$symlink_home/.local/bin/gemini" @google/gemini-cli
run_reconciler "$symlink_home"
[[ -L $symlink_home/.config/monarch/defaults/agent ]]
[[ ! -e $symlink_home/.local/bin/gemini ]]
[[ $(<"$symlink_home/preferences/agent") == "gemini" ]] ||
  fail "a symlinked default-agent preference was overwritten"
[[ $(HOME="$symlink_home" "$ROOT/bin/monarch-default-agent") == "agy" ]] ||
  fail "a symlinked legacy preference did not resolve to Antigravity"
pass "a symlinked agent preference remains user-owned"

failure_home="$test_tmp/interrupted"
prepare_home "$failure_home" gemini
write_direct_wrapper "$failure_home/.local/bin/codex" @openai/codex
write_direct_wrapper "$failure_home/.local/bin/gemini" @google/gemini-cli
write_direct_wrapper "$failure_home/.local/bin/opencode" opencode-ai
failure_bin="$test_tmp/failure-bin"
mkdir -p "$failure_bin"
cat >"$failure_bin/monarch-mise-install" <<'EOF'
#!/bin/bash
command=${2:-$1}
[[ $command != "opencode" ]] || exit 75
exec "$REAL_MISE_INSTALL" "$@"
EOF
chmod +x "$failure_bin/monarch-mise-install"
: >"$TEST_DROP_CALLS"
if REAL_MISE_INSTALL="$ROOT/bin/monarch-mise-install" HOME="$failure_home" \
  PATH="$failure_bin:$PATH" bash "$agent_reconciler" >/dev/null 2>&1; then
  fail "an interrupted wrapper refresh returned success"
fi
assert_hash "$failure_home/.local/bin/gemini" \
  12cf78e12f1741b48b2be025801e74bdf009310025cbb8d0916c73be47382f12
[[ $(<"$failure_home/.config/monarch/defaults/agent") == "gemini" ]] ||
  fail "an interrupted wrapper refresh changed the default agent"
[[ -x $failure_home/.local/bin/opencode ]] ||
  fail "an interrupted wrapper refresh removed OpenCode before replacing it"
[[ ! -s $TEST_DROP_CALLS ]] ||
  fail "an interrupted wrapper refresh removed packaged agent commands"
run_reconciler "$failure_home"
assert_v5_catalog "$failure_home"
[[ $(<"$failure_home/.config/monarch/defaults/agent") == "agy" ]] ||
  fail "retrying the wrapper refresh did not normalize the default agent"
grep -qxF 'claude-code openai-codex opencode' "$TEST_DROP_CALLS" ||
  fail "packaged agent commands were not retired after their replacements succeeded"
pass "an interrupted agent refresh keeps every command recoverable"

retirement_failure_home="$test_tmp/interrupted-package-retirement"
prepare_home "$retirement_failure_home" claude
HOME="$retirement_failure_home" bash "$agent_reconciler"
: >"$TEST_DROP_CALLS"
if TEST_DROP_STATUS=23 HOME="$retirement_failure_home" bash "$system_reconciler"; then
  fail "a failed packaged-agent retirement returned success"
fi
retirement_state="$retirement_failure_home/.local/state/monarch/reconcile/1-to-2/system-after-user"
[[ ! -e $retirement_state ]] ||
  fail "a failed packaged-agent retirement published transition readiness"
HOME="$retirement_failure_home" bash "$system_reconciler"
[[ -f $retirement_state ]] ||
  fail "retrying packaged-agent retirement did not publish transition readiness"
(( $(grep -xcF 'claude-code openai-codex opencode' "$TEST_DROP_CALLS") == 2 )) ||
  fail "packaged-agent retirement did not retry the same package set"
pass "runtime readiness waits for packaged-agent retirement"

blocked_home="$test_tmp/blocked-package-retirement"
prepare_home "$blocked_home" claude
mkdir -p "$blocked_home/user-codex-directory"
ln -s "$blocked_home/user-codex-directory" "$blocked_home/.local/bin/codex"
: >"$TEST_DROP_CALLS"
run_reconciler "$blocked_home"
grep -qxF 'claude-code opencode' "$TEST_DROP_CALLS" ||
  fail "a packaged command was removed without an executable user replacement"
[[ -L $blocked_home/.local/bin/codex ]] ||
  fail "a user-owned Codex symlink was overwritten"
pass "packaged agents remain until their user command is executable"

custom_home="$test_tmp/custom"
prepare_home "$custom_home" gemini
cat >"$custom_home/.local/bin/codex" <<'EOF'
#!/bin/bash
echo user-codex
EOF
cat >"$custom_home/.local/bin/gemini" <<'EOF'
#!/bin/bash
package="@google/gemini-cli"
command="gemini"
echo user-gemini
EOF
cat >"$custom_home/.local/bin/claude" <<'EOF'
#!/bin/bash
echo user-claude
EOF
chmod +x "$custom_home/.local/bin/codex" "$custom_home/.local/bin/gemini" \
  "$custom_home/.local/bin/claude"
ln -s /opt/user-ori "$custom_home/.local/bin/ori"
ln -s /missing/user-omp "$custom_home/.local/bin/omp"
cp "$custom_home/.local/bin/codex" "$test_tmp/custom-codex"
cp "$custom_home/.local/bin/gemini" "$test_tmp/custom-gemini"
cp "$custom_home/.local/bin/claude" "$test_tmp/custom-claude"

run_reconciler "$custom_home"
cmp "$custom_home/.local/bin/codex" "$test_tmp/custom-codex" ||
  fail "a custom Codex command was overwritten"
cmp "$custom_home/.local/bin/gemini" "$test_tmp/custom-gemini" ||
  fail "a custom Gemini command was removed by a partial signature"
cmp "$custom_home/.local/bin/claude" "$test_tmp/custom-claude" ||
  fail "a custom V5-only command was overwritten"
[[ -L $custom_home/.local/bin/ori && $(readlink "$custom_home/.local/bin/ori") == "/opt/user-ori" ]] ||
  fail "a user symlink was overwritten"
[[ -L $custom_home/.local/bin/omp && $(readlink "$custom_home/.local/bin/omp") == "/missing/user-omp" ]] ||
  fail "a broken user symlink was overwritten"
[[ $(<"$custom_home/.config/monarch/defaults/agent") == "agy" ]] ||
  fail "a custom Gemini command prevented default-agent normalization"

agy_hash=$(sha256sum "$custom_home/.local/bin/agy")
run_reconciler "$custom_home"
[[ $(sha256sum "$custom_home/.local/bin/agy") == $agy_hash ]] ||
  fail "repeating agent reconciliation changed a canonical wrapper"
cmp "$custom_home/.local/bin/codex" "$test_tmp/custom-codex" ||
  fail "repeating agent reconciliation overwrote a custom command"
[[ ! -e $TEST_MISE_CALLS ]] || fail "agent reconciliation eagerly invoked mise"
pass "custom commands survive strict ownership checks and repeated reconciliation"
