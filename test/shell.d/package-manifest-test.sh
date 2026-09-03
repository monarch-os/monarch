#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
source "$ROOT/install/helpers/package-manifest.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

manifest="$ROOT/install/monarch-base.packages"
required=()
defaults=()
all=()

monarch_load_package_manifest required "$manifest" required
monarch_load_package_manifest defaults "$manifest" default
monarch_load_package_manifest all "$manifest"

((${#required[@]})) || fail "required package section is populated"
((${#defaults[@]})) || fail "default package section is populated"
((${#all[@]} == ${#required[@]} + ${#defaults[@]})) ||
  fail "all packages combine both manifest sections"

declare -A required_packages=()
declare -A default_packages=()
declare -A all_packages=()
for package in "${required[@]}"; do
  required_packages[$package]=true
done
for package in "${defaults[@]}"; do
  default_packages[$package]=true
done
for package in "${all[@]}"; do
  all_packages[$package]=true
done

for package in chromium fuzzel gpu-screen-recorder grim localsend mpv neovim niri noctalia networkmanager sddm slurp uwsm yay zbar; do
  [[ -v required_packages[$package] ]] || fail "$package is a required package"
done

for package in firefox obsidian signal-desktop; do
  [[ -v default_packages[$package] ]] || fail "$package is a default package"
done

for package in claude-code opencode; do
  [[ ! -v all_packages[$package] ]] || fail "$package is mise-managed, not a pacman base package"
done

if ((${#all[@]} != $(printf '%s\n' "${all[@]}" | sort -u | wc -l))); then
  fail "package manifest contains duplicate packages"
fi

invalid="$TEST_ROOT/package-manifest"
printf '%s\n' orphan '# required' niri >"$invalid"
if monarch_load_package_manifest all "$invalid" 2>/dev/null; then
  fail "packages before the first section are rejected"
fi

printf '%s\n' '# required' niri >"$invalid"
if monarch_load_package_manifest defaults "$invalid" default 2>/dev/null; then
  fail "missing requested sections are rejected"
fi

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ROOT/installed-packages"
EOF
cat >"$TEST_ROOT/bin/pacman" <<'EOF'
#!/bin/bash
[[ $1 == "-Qq" ]]
EOF
chmod +x "$TEST_ROOT/bin/monarch-pkg-add" "$TEST_ROOT/bin/pacman"
TEST_ROOT="$TEST_ROOT" MONARCH_PATH="$ROOT" PATH="$TEST_ROOT/bin:/usr/bin" \
  bash "$ROOT/install/reconcile/required-packages.sh"
mapfile -t installed <"$TEST_ROOT/installed-packages"
[[ ${installed[*]} == ${required[*]} ]] || fail "reconciliation installs exactly the required packages"

pass "package manifest sections are valid"
