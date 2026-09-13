#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export MONARCH_THEME_BUNDLES_DIR="$TEST_ROOT/bundles"
export MONARCH_THEME_PALETTES_DIR="$TEST_ROOT/palettes"
export MONARCH_THEME_BACKGROUNDS_DIR="$TEST_ROOT/backgrounds"
mkdir -p "$HOME" "$TEST_ROOT/bin" "$TEST_ROOT/runtime/bin"

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
if [[ -f $HOME/active-theme ]]; then
  printf 'custom %s\n' "$(cat "$HOME/active-theme")"
fi
EOF
chmod +x "$TEST_ROOT/bin/noctalia"
cat >"$TEST_ROOT/runtime/bin/monarch-theme-set-browser-policy" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEST_ROOT/runtime/bin/monarch-theme-set-browser-policy"
export PATH="$TEST_ROOT/bin:$PATH"

make_theme() {
  local repo=$1 name=$2 id=$3
  mkdir -p "$repo/backgrounds"
  cp "$ROOT/config/noctalia/palettes/Monarch.json" "$repo/palette.json"
  cp "$ROOT/themes/monarch/1-monarch.png" "$repo/backgrounds/wallpaper.png"
  cp "$ROOT/themes/monarch/preview.png" "$repo/preview.png"
  jq -n --arg id "$id" --arg name "$name" \
    '{schema:1, id:$id, name:$name, palette:"palette.json", backgrounds:"backgrounds", preview:"preview.png"}' \
    >"$repo/monarch-theme.json"
  git -C "$repo" init -q
  git -C "$repo" add .
  git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
}

repo="$TEST_ROOT/aurora"
make_theme "$repo" Aurora aurora
result=$("$ROOT/bin/monarch-theme-bundle" install "file://$repo")
[[ $result == $'aurora\tAurora' ]]
[[ -f "$MONARCH_THEME_BUNDLES_DIR/aurora/provenance.json" ]]
[[ -L "$MONARCH_THEME_PALETTES_DIR/Aurora.json" ]]
[[ $(readlink -f "$MONARCH_THEME_PALETTES_DIR/Aurora.json") == "$MONARCH_THEME_BUNDLES_DIR/aurora/palette.json" ]]
jq -e --arg origin "file://$repo" '.schema == 1 and .origin == $origin and (.revision | length == 40)' \
  "$MONARCH_THEME_BUNDLES_DIR/aurora/provenance.json" >/dev/null
printf 'Aurora\n' >"$HOME/active-theme"
listed=$(MONARCH_PATH="$TEST_ROOT/runtime" "$ROOT/bin/monarch-theme-list")
[[ $listed == true$'\t'Aurora$'\t'aurora$'\t'"$MONARCH_THEME_BUNDLES_DIR/aurora/preview.png" ]]
MONARCH_PATH="$TEST_ROOT/runtime" "$ROOT/bin/monarch-theme-apply"
[[ $(readlink -f "$MONARCH_THEME_BACKGROUNDS_DIR/current/wallpaper.png") == "$MONARCH_THEME_BUNDLES_DIR/aurora/backgrounds/wallpaper.png" ]]

mkdir -p "$MONARCH_THEME_BACKGROUNDS_DIR/aurora"
printf 'personal\n' >"$MONARCH_THEME_BACKGROUNDS_DIR/aurora/personal.png"
old_revision=$(jq -r .revision "$MONARCH_THEME_BUNDLES_DIR/aurora/provenance.json")
printf '#!/bin/bash\n' >"$repo/install.sh"
chmod +x "$repo/install.sh"
git -C "$repo" add install.sh
git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm invalid
if "$ROOT/bin/monarch-theme-bundle" update aurora >/dev/null 2>&1; then
  echo "An executable theme update was accepted" >&2
  exit 1
fi
[[ $(jq -r .revision "$MONARCH_THEME_BUNDLES_DIR/aurora/provenance.json") == "$old_revision" ]]
[[ -f "$MONARCH_THEME_BACKGROUNDS_DIR/aurora/personal.png" ]]

git -C "$repo" rm -q install.sh
cp "$ROOT/themes/monarch/2-moon.jpg" "$repo/backgrounds/second.jpg"
git -C "$repo" add .
git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm update
"$ROOT/bin/monarch-theme-bundle" update aurora >/dev/null
new_revision=$(jq -r .revision "$MONARCH_THEME_BUNDLES_DIR/aurora/provenance.json")
[[ $new_revision != "$old_revision" ]]
[[ -f "$MONARCH_THEME_BUNDLES_DIR/aurora/backgrounds/second.jpg" ]]
[[ -f "$MONARCH_THEME_BACKGROUNDS_DIR/aurora/personal.png" ]]

if "$ROOT/bin/monarch-theme-bundle" remove aurora >/dev/null 2>&1; then
  echo "The active theme was removed" >&2
  exit 1
fi
[[ -d "$MONARCH_THEME_BUNDLES_DIR/aurora" ]]

printf 'Monarch\n' >"$HOME/active-theme"
"$ROOT/bin/monarch-theme-bundle" remove aurora >/dev/null
[[ ! -e "$MONARCH_THEME_BUNDLES_DIR/aurora" ]]
[[ ! -e "$MONARCH_THEME_PALETTES_DIR/Aurora.json" ]]
[[ -f "$MONARCH_THEME_BACKGROUNDS_DIR/aurora/personal.png" ]]

minimal="$TEST_ROOT/minimal"
make_theme "$minimal" Minimal minimal
git -C "$minimal" rm -q preview.png
jq 'del(.preview)' "$minimal/monarch-theme.json" >"$minimal/manifest.tmp"
mv "$minimal/manifest.tmp" "$minimal/monarch-theme.json"
git -C "$minimal" add monarch-theme.json
git -C "$minimal" -c user.name=Test -c user.email=test@example.invalid commit -qm minimal
"$ROOT/bin/monarch-theme-bundle" install "file://$minimal" >/dev/null
jq -e '.preview == ""' "$MONARCH_THEME_BUNDLES_DIR/minimal/provenance.json" >/dev/null
"$ROOT/bin/monarch-theme-bundle" remove minimal >/dev/null

unsafe="$TEST_ROOT/unsafe"
make_theme "$unsafe" Unsafe unsafe
ln -s /etc/passwd "$unsafe/backgrounds/passwd.png"
git -C "$unsafe" add backgrounds/passwd.png
git -C "$unsafe" -c user.name=Test -c user.email=test@example.invalid commit -qm unsafe
if "$ROOT/bin/monarch-theme-bundle" install "file://$unsafe" >/dev/null 2>&1; then
  echo "A theme containing a symbolic link was accepted" >&2
  exit 1
fi
[[ ! -e "$MONARCH_THEME_BUNDLES_DIR/unsafe" ]]

if "$ROOT/bin/monarch-theme-bundle" install 'ext::sh -c id' >/dev/null 2>&1; then
  echo "An executable Git transport was accepted" >&2
  exit 1
fi

monarch-theme-bundle() {
  case $1 in
  install | update) printf 'q5-test\tQ5 Test\n' ;;
  remove) printf 'Q5 Test\n' ;;
  list) printf 'q5-test\tQ5 Test\tdeadbeef\thttps://example.com/q5-test.git\n' ;;
  esac
}

monarch-theme-set() {
  [[ $1 == "Q5 Test" ]]
}

gum() {
  case $1 in
  choose) head -n 1 ;;
  confirm) printf '%s\n' "$*" >"$HOME/gum-confirm" ;;
  esac
}

export -f monarch-theme-bundle monarch-theme-set gum
output=$("$ROOT/bin/monarch-theme-install" https://example.com/q5-test.git)
[[ $output == $'Downloading and validating theme...\nApplying Q5 Test...\nInstalled and applied Q5 Test (q5-test)' ]]

output=$("$ROOT/bin/monarch-theme-update" q5-test)
[[ $output == $'Downloading and validating Q5 Test...\nUpdated Q5 Test (q5-test)' ]]

printf 'Q5 Test\n' >"$HOME/active-theme"
output=$("$ROOT/bin/monarch-theme-update" q5-test)
[[ $output == $'Downloading and validating Q5 Test...\nReapplying Q5 Test...\nUpdated Q5 Test (q5-test)' ]]

output=$("$ROOT/bin/monarch-theme-remove")
[[ $output == $'Removing Q5 Test...\nRemoved Q5 Test' ]]
[[ $(<"$HOME/gum-confirm") == "confirm Remove Q5 Test?" ]]

echo ok
