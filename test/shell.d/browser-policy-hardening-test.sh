#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
helper="$ROOT/bin/monarch-theme-set-browser-policy"
sudoers="$ROOT/etc/sudoers.d/monarch-theme-browser"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin"
for command in sudo pkexec; do
  cat >"$TEST_ROOT/bin/$command" <<'EOF'
#!/bin/bash
touch "$ELEVATION_MARKER"
exit 1
EOF
  chmod +x "$TEST_ROOT/bin/$command"
done

if PATH="$TEST_ROOT/bin:/usr/bin" ELEVATION_MARKER="$TEST_ROOT/elevated" \
  "$helper" AABBCC >/dev/null 2>&1; then
  echo "Uppercase color was accepted" >&2
  exit 1
fi
[[ ! -e $TEST_ROOT/elevated ]]

if PATH="$TEST_ROOT/bin:/usr/bin" ELEVATION_MARKER="$TEST_ROOT/elevated" \
  "$helper" aabbcc extra >/dev/null 2>&1; then
  echo "Extra argument was accepted" >&2
  exit 1
fi
[[ ! -e $TEST_ROOT/elevated ]]

grep -qF 'PACKAGED_PATH=/usr/bin/monarch-theme-set-browser-policy' "$helper"
grep -qF '[[ $color =~ ^[0-9a-f]{6}$ ]]' "$helper"
grep -qF 'install -m 0644 -o root -g root -T' "$helper"
grep -qF '[[ -d $policy_dir && ! -L $policy_dir ]]' "$helper"
grep -qF 'browser_policy_file_trusted "$entry" || as_root rm -rf -- "$entry"' \
  "$ROOT/install/helpers/browser-policy.sh"
grep -qF '/usr/bin/monarch-theme-set-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]' "$sudoers"

! rg -q 'chmod (a\+rw|77[0-9])' "$ROOT/install" "$ROOT/bin"
grep -qF 'browser_policy_setup_dir /etc/chromium/policies/managed' \
  "$ROOT/install/config/browser-policy.sh"
grep -qF 'install/reconcile/browser-policy.sh' "$ROOT/install/reconcile/system.sh"
grep -qF '"$MONARCH_ROOT/bin/monarch-theme-set-browser-policy" "${hex,,}"' \
  "$ROOT/bin/monarch-theme-apply"
grep -qF '"require_eula":false' "$ROOT/install/config/theme-system.sh"

echo "Browser policy hardening checks pass"
