#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/system/etc/sudoers.d" \
  "$test_tmp/system/usr/share/sddm/themes/monarch"
touch "$test_tmp/system/etc/sudoers.d/monarch-tzupdate"
chmod 000 "$test_tmp/system/etc/sudoers.d"
touch "$test_tmp/system/usr/share/sddm/themes/monarch/theme.conf"

cat >"$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
[[ $1 != "-Qo" ]]
EOF

cat >"$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
if [[ $1 == "test" && $3 == */etc/sudoers.d/monarch-tzupdate ]]; then
  exit 0
fi
exec "$@"
EOF

cat >"$test_tmp/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
EOF

chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:/usr/bin"
export TEST_LOG="$test_tmp/calls"
export MONARCH_LEGACY_SYSTEM_ROOT="$test_tmp/system"

source "$ROOT/install/reconcile/packaged-runtime-bootstrap.sh"
monarch_install_packaged_runtime true

grep -qF -- '--overwrite etc/sudoers.d/monarch-tzupdate' "$TEST_LOG"
grep -qF -- '--overwrite usr/share/sddm/themes/monarch/theme.conf' "$TEST_LOG"
grep -qF -- ' monarch' "$TEST_LOG"
! grep -q '^pkg-add ' "$TEST_LOG"
chmod 700 "$test_tmp/system/etc/sudoers.d"

: >"$TEST_LOG"
rm -rf "$test_tmp/system/usr/share/sddm"
monarch_install_packaged_runtime true
grep -qF -- '--overwrite etc/sudoers.d/monarch-tzupdate' "$TEST_LOG"
! grep -q '^pkg-add ' "$TEST_LOG"

cat >"$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
[[ $1 == "-Qo" ]]
EOF
chmod +x "$test_tmp/bin/pacman"
mkdir -p "$test_tmp/system/etc/sudoers.d"
touch "$test_tmp/system/etc/sudoers.d/monarch-tzupdate"

if monarch_install_packaged_runtime true 2>/dev/null; then
  echo "package-owned legacy path was overwritten" >&2
  exit 1
fi
! grep -q '^-S ' "$TEST_LOG"

: >"$TEST_LOG"
cat >"$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
exit 1
EOF
chmod +x "$test_tmp/bin/pacman"
monarch_install_packaged_runtime false
grep -qx 'pkg-add monarch' "$TEST_LOG"
! grep -q '^-S ' "$TEST_LOG"

echo "Packaged runtime bootstrap tests passed."
