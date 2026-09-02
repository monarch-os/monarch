#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
source "$ROOT/install/helpers/package-manifest.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

manifest="$ROOT/install/monarch-base.packages"
required=()
preinstalled=()
all=()

monarch_load_package_manifest required "$manifest" required
monarch_load_package_manifest preinstalled "$manifest" preinstalled
monarch_load_package_manifest all "$manifest"

((${#required[@]})) || fail "required package section is populated"
((${#preinstalled[@]})) || fail "preinstalled package section is populated"
((${#all[@]} == ${#required[@]} + ${#preinstalled[@]})) ||
  fail "all packages combine both manifest sections"

for package in chromium fuzzel gpu-screen-recorder grim localsend mpv neovim niri noctalia networkmanager sddm slurp uwsm yay zbar; do
  [[ " ${required[*]} " == *" $package "* ]] || fail "$package is a required package"
done

for package in firefox obsidian signal-desktop; do
  [[ " ${preinstalled[*]} " == *" $package "* ]] || fail "$package is a preinstalled package"
done

if ((${#all[@]} != $(printf '%s\n' "${all[@]}" | sort -u | wc -l))); then
  fail "package manifest contains no duplicates"
fi

invalid="$TEST_ROOT/package-manifest"
printf '%s\n' orphan '# required' niri >"$invalid"
if monarch_load_package_manifest all "$invalid" 2>/dev/null; then
  fail "packages before the first section are rejected"
fi

printf '%s\n' '# required' niri >"$invalid"
if monarch_load_package_manifest preinstalled "$invalid" preinstalled 2>/dev/null; then
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
[[ ${installed[*]} == "${required[*]}" ]] || fail "reconciliation installs exactly the required packages"

pass "package manifest sections are valid"
