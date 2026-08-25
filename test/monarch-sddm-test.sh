#!/bin/bash

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export MONARCH_PATH="$ROOT"
export MONARCH_SDDM_THEME_DIR="$TMP_ROOT/sddm"
export PATH="$TMP_ROOT/bin:$ROOT/bin:$PATH"
mkdir -p "$HOME" "$MONARCH_SDDM_THEME_DIR" "$TMP_ROOT/bin"
touch "$MONARCH_SDDM_THEME_DIR/logo.png"
cp "$ROOT/default/sddm/monarch/theme.conf" "$MONARCH_SDDM_THEME_DIR/theme.conf"

cat >"$TMP_ROOT/bin/monarch-theme-colors" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"mPrimary":"#010203","mOnPrimary":"#040506","mSecondary":"#070809","mOnSecondary":"#0a0b0c","mTertiary":"#0d0e0f","mOnTertiary":"#101112","mError":"#131415","mOnError":"#161718","mSurface":"#191a1b","mOnSurface":"#1c1d1e","mSurfaceVariant":"#1f2021","mOnSurfaceVariant":"#222324","mOutline":"#252627","mShadow":"#28292a"}
JSON
EOF
chmod +x "$TMP_ROOT/bin/monarch-theme-colors"

cat >"$TMP_ROOT/bin/magick" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$MAGICK_CALL"
EOF
chmod +x "$TMP_ROOT/bin/magick"
export MAGICK_CALL="$TMP_ROOT/magick-call"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

"$ROOT/bin/monarch-sddm-apply"

grep -qx 'mPrimary=#010203' "$MONARCH_SDDM_THEME_DIR/theme.conf" || fail "writes the primary color"
grep -qx 'mSurface=#191a1b' "$MONARCH_SDDM_THEME_DIR/theme.conf" || fail "writes the surface color"
[[ $(wc -l <"$MONARCH_SDDM_THEME_DIR/theme.conf") == 15 ]] || fail "writes the complete theme"
pass "writes the complete SDDM palette"

grep -q '#010203,#010203' "$MAGICK_CALL" || fail "recolors the logo from the primary color"
pass "recolors the logo"

sed -i 's/#191a1b/not-a-color/' "$TMP_ROOT/bin/monarch-theme-colors"
before=$(sha256sum "$MONARCH_SDDM_THEME_DIR/theme.conf")
"$ROOT/bin/monarch-sddm-apply"
after=$(sha256sum "$MONARCH_SDDM_THEME_DIR/theme.conf")
[[ $before == "$after" ]] || fail "rejects an invalid palette before writing"
pass "rejects an invalid palette before writing"

grep -qx 'monarch-sddm-apply' "$ROOT/bin/monarch-theme-apply" || fail "theme hook applies SDDM"
pass "theme hook applies SDDM"
