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

skill_dirs=(
  .agents/skills
  .claude/skills
  .codex/skills
  .pi/agent/skills
  .gemini/config/skills
)

assert_skills() {
  local skill_dir skill link

  for skill_dir in "${skill_dirs[@]}"; do
    for skill in monarch diagnose-crash; do
      link="$test_tmp/home/$skill_dir/$skill"
      [[ -L $link && $(readlink "$link") == $ROOT/default/agents/skills/$skill ]] ||
        fail "monarch-provision-user provisions $skill for $skill_dir"
    done
  done
}

assert_skills
pass "monarch-provision-user provisions agent skills for every supported client"

legacy_skill="$test_tmp/home/.local/share/monarch/default/monarch-skill"
for skill_dir in "${skill_dirs[@]:0:4}"; do
  ln -sfn "$legacy_skill" "$test_tmp/home/$skill_dir/monarch"
done
rm "$test_tmp/home/.gemini/config/skills/monarch"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" MONARCH_PATH="$ROOT" \
  MONARCH_INSTALL="$test_tmp/install" bash "$ROOT/bin/monarch-provision-user" --force >/dev/null ||
  fail "monarch-provision-user repairs legacy agent skills"

assert_skills
pass "monarch-provision-user repairs legacy agent skills"

custom_skill_dir="$test_tmp/home/.codex/skills/monarch"
custom_skill_file="$test_tmp/home/.claude/skills/monarch"
rm "$custom_skill_dir" "$custom_skill_file"
mkdir "$custom_skill_dir"
printf '%s\n' '# User-owned Monarch skill' >"$custom_skill_dir/SKILL.md"
printf '%s\n' 'user-owned skill reference' >"$custom_skill_file"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" MONARCH_PATH="$ROOT" \
  MONARCH_INSTALL="$test_tmp/install" bash "$ROOT/bin/monarch-provision-user" --force >/dev/null ||
  fail "monarch-provision-user preserves a user-owned skill directory"

[[ -d $custom_skill_dir && ! -L $custom_skill_dir ]] ||
  fail "monarch-provision-user replaced a user-owned skill directory"
[[ $(<"$custom_skill_dir/SKILL.md") == "# User-owned Monarch skill" ]] ||
  fail "monarch-provision-user changed a user-owned skill"
[[ ! -e $custom_skill_dir/monarch && ! -L $custom_skill_dir/monarch ]] ||
  fail "monarch-provision-user nested a managed skill inside a user-owned directory"
[[ -f $custom_skill_file && ! -L $custom_skill_file ]] ||
  fail "monarch-provision-user replaced a user-owned skill file"
[[ $(<"$custom_skill_file") == "user-owned skill reference" ]] ||
  fail "monarch-provision-user changed a user-owned skill file"
pass "monarch-provision-user preserves user-owned skill paths"

[[ $(<"$test_tmp/home/.local/state/monarch/schema") == 2 ]] ||
  fail "fresh installs record the current reconciliation schema"
pass "monarch-provision-user records the current reconciliation schema"
