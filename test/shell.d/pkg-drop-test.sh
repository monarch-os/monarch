#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_PACMAN_LOG"
if [[ $1 == "-Qq" ]]; then
  printf '%s\n' noctalia-shell polkit-gnome
fi
EOF
cat >"$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x "$test_tmp/bin/pacman" "$test_tmp/bin/sudo"

export PATH="$test_tmp/bin:/usr/bin"
export TEST_PACMAN_LOG="$test_tmp/pacman.log"

"$ROOT/bin/monarch-pkg-drop" --keep-dependencies noctalia-shell missing
grep -qx -- '-R --noconfirm noctalia-shell' "$TEST_PACMAN_LOG"
pass "package retirement can preserve shared dependencies"

: >"$TEST_PACMAN_LOG"
"$ROOT/bin/monarch-pkg-drop" polkit-gnome
grep -qx -- '-Rns --noconfirm polkit-gnome' "$TEST_PACMAN_LOG"
pass "ordinary package retirement still removes orphaned dependencies"

: >"$TEST_PACMAN_LOG"
"$ROOT/bin/monarch-pkg-drop" --cascade polkit-gnome
grep -qx -- '-Rns --noconfirm --cascade polkit-gnome' "$TEST_PACMAN_LOG"
pass "cascade retirement keeps its explicit dependent-removal mode"
