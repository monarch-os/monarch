#!/bin/bash

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ABOUT="$ROOT/bin/monarch-launch-about"
failures=0

source "$ABOUT"

assert_equals() {
  local description=$1
  local actual=$2
  local expected=$3

  if [[ $actual == "$expected" ]]; then
    echo "ok - $description"
  else
    echo "not ok - $description (expected '$expected', got '$actual')"
    ((failures++))
  fi
}

padding_value() {
  local config=$1
  local key=$2

  sed -n "s/.*\"$key\": \([0-9]*\).*/\1/p" "$config" | head -n 1
}

assert_equals "wide terminals use the full layout" \
  "$(COLUMNS=104 LINES=30 "$ABOUT" --layout)" "full"
assert_equals "narrow terminals use the compact layout" \
  "$(COLUMNS=103 LINES=40 "$ABOUT" --layout)" "compact"
assert_equals "short terminals use the compact layout" \
  "$(COLUMNS=140 LINES=29 "$ABOUT" --layout)" "compact"
assert_equals "system config optically centers the full logo" \
  "$(padding_value "$ROOT/etc/fastfetch/config.jsonc" left)" "8"
assert_equals "system config keeps the information column fixed" \
  "$(padding_value "$ROOT/etc/fastfetch/config.jsonc" right)" "0"
assert_equals "full layout uses a uniform double-colon marker" \
  "$(grep -c '"key": ".*::' "$ROOT/etc/fastfetch/config.jsonc")" "21"
assert_equals "full layout removes tree-shaped module keys" \
  "$(grep -Ec '"key": ".*[├└]' "$ROOT/etc/fastfetch/config.jsonc")" "0"
assert_equals "vertical borders use the frame color" \
  "$(grep -Fc '"key": "\u001b[90m│' "$ROOT/etc/fastfetch/config.jsonc")" "21"
assert_equals "module keys do not recolor their borders" \
  "$(grep -c '"keyColor"' "$ROOT/etc/fastfetch/config.jsonc")" "0"
assert_equals "hardware values use concise formats" \
  "$(grep -c '"format": "{' "$ROOT/etc/fastfetch/config.jsonc")" "7"
assert_equals "variable hardware names stay within the frame" \
  "$(grep -c '"format": ".*:-44' "$ROOT/etc/fastfetch/config.jsonc")" "3"

CASE_DIR=$(mktemp -d)
trap 'rm -rf "$CASE_DIR"' EXIT
mkdir -p "$CASE_DIR/home/.config/monarch/branding" \
  "$CASE_DIR/runtime" "$CASE_DIR/system-fastfetch"
cp "$ROOT/icon.txt" "$CASE_DIR/runtime/icon.txt"
cp "$ROOT/icon.txt" "$CASE_DIR/home/.config/monarch/branding/about.txt"
export ABOUT_FASTFETCH_DIR="$CASE_DIR/system-fastfetch"

cat >"$CASE_DIR/fastfetch" <<'EOF'
#!/bin/bash
if [[ ${1:-} == "--list-config-paths" ]]; then
  printf '%s\n' "$HOME/.config/fastfetch/" "$ABOUT_FASTFETCH_DIR/ (*)"
  exit 0
fi
for ((line = 1; line <= 27; line++)); do
  printf 'rendered %d\n' "$line"
done
EOF

cat >"$CASE_DIR/tte" <<EOF
#!/bin/bash
printf '%s ' "\$@" >"$CASE_DIR/tte.args"
cat >"$CASE_DIR/tte.input"
EOF
chmod +x "$CASE_DIR/fastfetch" "$CASE_DIR/tte"

about_terminal_supports_sheen() { return 0; }
PATH="$CASE_DIR:$PATH" HOME="$CASE_DIR/home" \
  about_render_full "$CASE_DIR/runtime" >/dev/null

animation_args=$(<"$CASE_DIR/tte.args")
[[ $animation_args == *"--existing-color-handling dynamic"* ]] ||
  { echo "not ok - sheen preserves the stock ANSI colors"; ((failures++)); }
[[ $animation_args == *"--frame-rate 144"* ]] ||
  { echo "not ok - sheen uses the calibrated frame rate"; ((failures++)); }
[[ $animation_args == *"diagonal_top_left_to_bottom_right"* ]] ||
  { echo "not ok - sheen crosses the logo diagonally"; ((failures++)); }
[[ $(head -n 1 "$CASE_DIR/tte.input" | cut -c 1-8) == "        " ]] ||
  { echo "not ok - sheen follows the optically centered logo"; ((failures++)); }

rm -f "$CASE_DIR/tte.args"
mkdir -p "$CASE_DIR/home/.config/fastfetch"
touch "$CASE_DIR/home/.config/fastfetch/config.jsonc"
PATH="$CASE_DIR:$PATH" HOME="$CASE_DIR/home" \
  about_render_full "$CASE_DIR/runtime" >/dev/null
[[ ! -e $CASE_DIR/tte.args ]] ||
  { echo "not ok - a custom Fastfetch layout remains static"; ((failures++)); }

rm "$CASE_DIR/home/.config/fastfetch/config.jsonc"
printf 'custom logo\n' >"$CASE_DIR/home/.config/monarch/branding/about.txt"
PATH="$CASE_DIR:$PATH" HOME="$CASE_DIR/home" \
  about_render_full "$CASE_DIR/runtime" >/dev/null
[[ ! -e $CASE_DIR/tte.args ]] ||
  { echo "not ok - custom About branding remains static"; ((failures++)); }

if (( failures > 0 )); then
  echo
  echo "$failures test(s) failed."
  exit 1
fi

echo
echo "All About tests passed."
