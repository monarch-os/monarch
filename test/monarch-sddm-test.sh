#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export MONARCH_PATH="$ROOT"
export MONARCH_UNLOCK_TEST_ROOT="$TMP_ROOT/system"
export PATH="$TMP_ROOT/bin:$ROOT/bin:/usr/bin:/bin"

mkdir -p \
  "$HOME" \
  "$TMP_ROOT/bin" \
  "$MONARCH_UNLOCK_TEST_ROOT/tmp" \
  "$MONARCH_UNLOCK_TEST_ROOT/usr/bin" \
  "$MONARCH_UNLOCK_TEST_ROOT/usr/share/monarch/default" \
  "$MONARCH_UNLOCK_TEST_ROOT/usr/share/plymouth/themes/monarch/logos" \
  "$MONARCH_UNLOCK_TEST_ROOT/usr/share/sddm/themes/monarch"
cp -a "$ROOT/default/plymouth" "$ROOT/default/sddm" \
  "$MONARCH_UNLOCK_TEST_ROOT/usr/share/monarch/default/"

cat >"$TMP_ROOT/bin/monarch-theme-colors" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"mPrimary":"#010203","mOnPrimary":"#040506","mSecondary":"#070809","mOnSecondary":"#0a0b0c","mTertiary":"#0d0e0f","mOnTertiary":"#101112","mError":"#131415","mOnError":"#161718","mSurface":"#191a1b","mOnSurface":"#1c1d1e","mSurfaceVariant":"#1f2021","mOnSurfaceVariant":"#222324","mOutline":"#252627","mShadow":"#28292a"}
JSON
EOF
cat >"$TMP_ROOT/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$TMP_ROOT/bin/plymouth-set-default-theme" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$HOME/plymouth-call"
EOF
cat >"$TMP_ROOT/bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$HOME/limine-call"
EOF
cat >"$TMP_ROOT/bin/magick" <<'EOF'
#!/bin/bash
exit 0
EOF
cp "$TMP_ROOT/bin/magick" "$MONARCH_UNLOCK_TEST_ROOT/usr/bin/magick"
chmod +x "$TMP_ROOT/bin/monarch-theme-colors" "$TMP_ROOT/bin/sudo" \
  "$TMP_ROOT/bin/plymouth-set-default-theme" "$TMP_ROOT/bin/limine-mkinitcpio" \
  "$TMP_ROOT/bin/magick" "$MONARCH_UNLOCK_TEST_ROOT/usr/bin/magick"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

plymouth="$MONARCH_UNLOCK_TEST_ROOT/usr/share/plymouth/themes/monarch"
sddm="$MONARCH_UNLOCK_TEST_ROOT/usr/share/sddm/themes/monarch"
victim="$TMP_ROOT/victim"
printf 'must survive\n' >"$victim"
chmod 0600 "$victim"
ln -s "$victim" "$plymouth/monarch.script"
ln -s "$victim" "$sddm/theme.conf"
ln -s "$victim" "$sddm/logo.png"

"$ROOT/bin/monarch-plymouth-apply" Monarch >/dev/null

[[ -f $plymouth/monarch.script && ! -L $plymouth/monarch.script ]] ||
  fail "Plymouth publication replaces a destination symlink"
[[ -f $sddm/theme.conf && ! -L $sddm/theme.conf ]] ||
  fail "SDDM publication replaces a destination symlink"
[[ -f $sddm/logo.png && ! -L $sddm/logo.png ]] ||
  fail "SDDM logo publication replaces a destination symlink"
[[ $(<"$victim") == "must survive" ]] || fail "publication overwrites a symlink victim"
pass "atomic publication does not follow hostile destination symlinks"

for published in "$plymouth/monarch.script" "$sddm/theme.conf" "$sddm/logo.png"; do
  [[ $(stat -c %a "$published") == "644" ]] || fail "$published is not mode 0644"
done
grep -qx 'mPrimary=#010203' "$sddm/theme.conf" || fail "writes the primary color"
grep -qx 'mSurface=#191a1b' "$sddm/theme.conf" || fail "writes the surface color"
[[ $(wc -l <"$sddm/theme.conf") == 15 ]] || fail "writes the complete SDDM palette"
[[ $(<"$HOME/.local/state/monarch/unlock-theme") == "Monarch" ]] ||
  fail "records the selected unlock theme"
[[ $(<"$HOME/plymouth-call") == "monarch" ]] || fail "activates the Plymouth theme"
[[ -f $HOME/limine-call ]] || fail "rebuilds the initramfs"
pass "theme apply keeps the palette and boot-image behavior"

plymouth_assets=(
  bullet.png entry.png lock.png logo.png monarch.plymouth monarch.script
  preview-unlock.png progress_bar.png progress_box.png logos/oma.png
)
sddm_assets=(
  Main.qml bullet.png entry-failed.png entry.png lock-failed.png lock.png
  logo.png metadata.desktop theme.conf
)

packaged_plymouth=$(find "$ROOT/default/plymouth" -type f -printf '%P\n' | sort)
expected_plymouth=$(printf '%s\n' "${plymouth_assets[@]}" | sort)
[[ $packaged_plymouth == "$expected_plymouth" ]] || fail "Plymouth allowlist is incomplete"
packaged_sddm=$(find "$ROOT/default/sddm/monarch" -maxdepth 1 -type f -printf '%f\n' | sort)
expected_sddm=$(printf '%s\n' "${sddm_assets[@]}" | sort)
[[ $packaged_sddm == "$expected_sddm" ]] || fail "SDDM allowlist is incomplete"
pass "refresh allowlists cover every packaged unlock asset"

"$ROOT/bin/monarch-refresh-plymouth" >/dev/null
for asset in "${plymouth_assets[@]}"; do
  cmp -s "$ROOT/default/plymouth/$asset" "$plymouth/$asset" ||
    fail "Plymouth refresh misses $asset"
  [[ $(stat -c %a "$plymouth/$asset") == "644" ]] || fail "$asset is not mode 0644"
done
pass "Plymouth refresh publishes the fixed complete asset set"

"$ROOT/bin/monarch-refresh-sddm" >/dev/null
for asset in "${sddm_assets[@]}"; do
  cmp -s "$ROOT/default/sddm/monarch/$asset" "$sddm/$asset" ||
    fail "SDDM refresh misses $asset"
  [[ $(stat -c %a "$sddm/$asset") == "644" ]] || fail "$asset is not mode 0644"
done
pass "SDDM refresh restores root-published defaults without writable leaves"

chmod 0777 "$sddm"
before=$(sha256sum "$sddm/Main.qml")
if "$ROOT/bin/monarch-refresh-sddm" >/dev/null 2>&1; then
  fail "publication accepts a writable destination directory"
fi
after=$(sha256sum "$sddm/Main.qml")
[[ $before == "$after" ]] || fail "a rejected destination changed"
pass "publication fails closed on an untrusted destination parent"

chmod 0755 "$sddm"
source_bullet="$MONARCH_UNLOCK_TEST_ROOT/usr/share/monarch/default/plymouth/bullet.png"
mv "$source_bullet" "$source_bullet.original"
ln -s "$victim" "$source_bullet"
before=$(sha256sum "$plymouth/bullet.png")
set +e
output=$("$ROOT/bin/monarch-refresh-plymouth" 2>&1)
status=$?
set -e
rm "$source_bullet"
mv "$source_bullet.original" "$source_bullet"
((status != 0)) || fail "publication accepts a symlinked packaged asset"
after=$(sha256sum "$plymouth/bullet.png")
[[ $before == "$after" ]] || fail "a rejected source changed its destination"
[[ $output == *"refusing to publish"* ]] || fail "a rejected source fails silently"
pass "publication rejects untrusted packaged inputs before replacing destinations"

"$ROOT/bin/monarch-plymouth-reset" >/dev/null
[[ $(<"$HOME/.local/state/monarch/unlock-theme") == "default" ]] ||
  fail "reset does not record the default unlock theme"
pass "reset reuses both safe refresh paths"

cat >"$TMP_ROOT/bin/monarch-theme-colors" <<'EOF'
#!/bin/bash
exit 1
EOF
if ! "$ROOT/bin/monarch-sddm-apply"; then
  fail "SDDM apply rejects a builtin scheme with no custom palette"
fi
pass "SDDM apply preserves the no-palette no-op"

if grep -qE 'chmod +0?666|sudo +(cp|find|rm)|cp -a .*\$stage' \
  "$ROOT/bin/monarch-plymouth-apply" \
  "$ROOT/bin/monarch-plymouth-reset" \
  "$ROOT/bin/monarch-refresh-plymouth" \
  "$ROOT/bin/monarch-refresh-sddm" \
  "$ROOT/install/login/plymouth.sh" \
  "$ROOT/install/login/sddm.sh"; then
  fail "an unsafe publication primitive remains"
fi
pass "all interactive writers use the shared fixed-file publisher"
