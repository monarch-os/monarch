#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PATH="$TEST_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
if [[ ${1:-} == msg && ${2:-} == color-scheme-get ]]; then
  echo "custom Tokyo Night"
elif [[ ${1:-} == msg && ${2:-} == wallpaper-set ]]; then
  printf '%s\n' "$3" >"$HOME/applied"
elif [[ ${1:-} == msg && ${2:-} == panel-open ]]; then
  printf '%s\n' "$3" >"$HOME/reopened"
fi
EOF

cat >"$TEST_ROOT/bin/monarch-theme-apply" <<'EOF'
#!/bin/bash
find "$HOME/.config/monarch/backgrounds/tokyo-night" -maxdepth 1 -type f -printf '%f\n' >"$HOME/refreshed"
EOF

cat >"$TEST_ROOT/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TEST_ROOT/bin/monarch-file-select" <<'EOF'
#!/bin/bash
exit 1
EOF

chmod +x "$TEST_ROOT/bin/"*

panel="$ROOT/default/noctalia/plugins/monarch-theme/background.luau"
if ! grep -Fq 'noctalia.runAsync(BIN .. "/monarch-theme-background-import --reopen-panel")' "$panel"; then
  echo "Background imports are not detached from Noctalia's command timeout" >&2
  exit 1
fi

cp "$ROOT/themes/monarch/1-monarch.png" "$TEST_ROOT/wallpaper.png"
result=$("$ROOT/bin/monarch-theme-background-import" --reopen-panel "$TEST_ROOT/wallpaper.png")
expected="$HOME/.config/monarch/backgrounds/tokyo-night/wallpaper.png"

[[ $result == "$expected" ]]
[[ -f $expected ]]
grep -qx 'wallpaper.png' "$HOME/refreshed"
grep -qx "$expected" "$HOME/applied"
grep -qx 'monarch/theme:background' "$HOME/reopened"

result=$("$ROOT/bin/monarch-theme-background-import" "$TEST_ROOT/wallpaper.png")
[[ $result == "$HOME/.config/monarch/backgrounds/tokyo-night/wallpaper-2.png" ]]
[[ -f $result ]]

printf 'not an image\n' >"$TEST_ROOT/fake.png"
if "$ROOT/bin/monarch-theme-background-import" "$TEST_ROOT/fake.png" >/dev/null 2>&1; then
  echo "Non-image input was accepted" >&2
  exit 1
fi

rm "$HOME/reopened"
"$ROOT/bin/monarch-theme-background-import" --reopen-panel
grep -qx 'monarch/theme:background' "$HOME/reopened"

printf 'ok\n'
