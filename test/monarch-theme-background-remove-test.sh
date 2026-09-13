#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PATH="$TEST_ROOT/bin:$PATH"
export MONARCH_PATH="$TEST_ROOT/monarch"
user_dir="$HOME/.config/monarch/backgrounds/monarch"
shipped_dir="$MONARCH_PATH/themes/monarch"
mkdir -p "$user_dir" "$shipped_dir" "$TEST_ROOT/bin" "$TEST_ROOT/external"
touch "$user_dir/imported.png" "$user_dir/protected.png" "$shipped_dir/protected.png" "$TEST_ROOT/external/builtin.png"

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
[[ ${1:-} == msg && ${2:-} == color-scheme-get ]] && echo "custom Monarch"
EOF
cat >"$TEST_ROOT/bin/monarch-theme-apply" <<'EOF'
#!/bin/bash
touch "$HOME/refreshed"
EOF
cat >"$TEST_ROOT/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$TEST_ROOT/bin/gio" <<'EOF'
#!/bin/bash
shift 2
mv -- "$1" "$HOME/trashed.png"
EOF
chmod +x "$TEST_ROOT/bin/"*

"$ROOT/bin/monarch-theme-background-remove" "$user_dir/imported.png"
[[ ! -e $user_dir/imported.png && -f $HOME/trashed.png && -f $HOME/refreshed ]]

if "$ROOT/bin/monarch-theme-background-remove" "$TEST_ROOT/external/builtin.png" >/dev/null 2>&1; then
  echo "A shipped background was removable" >&2
  exit 1
fi
[[ -f $TEST_ROOT/external/builtin.png ]]

if "$ROOT/bin/monarch-theme-background-remove" "$user_dir/protected.png" >/dev/null 2>&1; then
  echo "A local copy of a shipped background was removable" >&2
  exit 1
fi
[[ -f $user_dir/protected.png ]]

printf 'ok\n'
