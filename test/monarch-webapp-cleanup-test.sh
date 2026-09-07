#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export PATH="$TMP/bin:$ROOT/bin:/usr/bin:/bin"
export MONARCH_PATH="$ROOT" WEBAPP_CLEANUP_LOG="$TMP/log"
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
mkdir -p "$TMP/bin" "$WEBAPP_CLEANUP_LOG"
cat > "$TMP/bin/find" <<'EOF'
#!/bin/bash
printf 'find\n' >> "$WEBAPP_CLEANUP_LOG/find"
if [[ $(wc -l < "$WEBAPP_CLEANUP_LOG/find") == "${WEBAPP_FIND_FAIL_AT:-0}" ]]; then exit 1; fi
exec /usr/bin/find "$@"
EOF
cat > "$TMP/bin/gtk-update-icon-cache" <<'EOF'
#!/bin/bash
printf 'cache\n' >> "$WEBAPP_CLEANUP_LOG/cache"
EOF
cat > "$TMP/bin/rm" <<'EOF'
#!/bin/bash
[[ -z ${WEBAPP_REMOVE_FAIL:-} || ${!#} != "$WEBAPP_REMOVE_FAIL" ]] || exit 23
exec /usr/bin/rm "$@"
EOF
cat > "$TMP/bin/update-desktop-database" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/"*

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reset_log() { : > "$WEBAPP_CLEANUP_LOG/find"; : > "$WEBAPP_CLEANUP_LOG/cache"; }
new_case() {
  export HOME="$TMP/$1"
  APP_DIR="$HOME/.local/share/applications"
  ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$APP_DIR/icons" "$ICON_DIR"
  reset_log
}
managed() {
  local name=$1 icon=${2:-$ICON_DIR/monarch-webapp-$1.png}
  [[ -e $icon ]] || printf 'owned fixture\n' > "$icon"
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=monarch-launch-webapp https://example.com\nIcon=%s\nX-Monarch-WebApp=true\nX-Monarch-WebApp-Icon=%s\n' \
    "$name" "${icon##*/}" "$icon" > "$APP_DIR/$name.desktop"
  sed -i 's/^Icon=\(.*\)\.png$/Icon=\1/' "$APP_DIR/$name.desktop"
}
borrowed() {
  printf '[Desktop Entry]\nType=Application\nExec=other-browser\nIcon=%s\n' "$2" > "$APP_DIR/$1.desktop"
}

for command in monarch-webapp-remove-all monarch-webapp-remove; do
  new_case "$command"
  for name in One Two Three Four; do managed "$name"; done
  arguments=()
  [[ $command != "monarch-webapp-remove" ]] || arguments=(One Two Three Four)
  "$command" "${arguments[@]}" > "$TMP/output"
  scans=$(wc -l < "$WEBAPP_CLEANUP_LOG/find")
  caches=$(wc -l < "$WEBAPP_CLEANUP_LOG/cache")
  printf '%s: %s inventories, %s cache refreshes\n' "$command" "$scans" "$caches"
  [[ $scans == 2 && $caches == 1 ]] || fail 'multiple removals repeat inventory or icon-cache work'
  [[ -z $(/usr/bin/find "$APP_DIR" "$ICON_DIR" -name '*.desktop' -o -name '*.png') ]] || fail 'batch cleanup left owned files'
done
printf 'PASS: bulk and selected removals share one cleanup inventory and cache refresh\n'

new_case shared
for name in Free Name Path Hardlink Symlink Action Marker; do managed "$name"; done
borrowed KeepName monarch-webapp-Name
borrowed KeepPath "$ICON_DIR/../apps/monarch-webapp-Path.png"
ln "$ICON_DIR/monarch-webapp-Hardlink.png" "$APP_DIR/icons/hardlink.png"
borrowed KeepHardlink "$APP_DIR/icons/hardlink.png"
ln -s "$ICON_DIR/monarch-webapp-Symlink.png" "$APP_DIR/icons/symlink.png"
borrowed KeepSymlink "$APP_DIR/icons/symlink.png"
borrowed KeepAction web-browser
printf '[Desktop Action Open]\nIcon=%s\n' "$ICON_DIR/monarch-webapp-Action.png" >> "$APP_DIR/KeepAction.desktop"
borrowed KeepMarker web-browser
printf 'X-Monarch-WebApp-Icon=%s\n' "$ICON_DIR/monarch-webapp-Marker.png" >> "$APP_DIR/KeepMarker.desktop"
monarch-webapp-remove Free Name Path Hardlink Symlink Action Marker > "$TMP/output"
[[ ! -e $ICON_DIR/monarch-webapp-Free.png ]] || fail 'unreferenced icon was not removed'
for name in Name Path Hardlink Symlink Action Marker; do
  [[ -f $ICON_DIR/monarch-webapp-$name.png ]] || fail "shared $name icon was removed"
  [[ -f $APP_DIR/Keep$name.desktop ]] || fail "unmanaged $name launcher was removed"
done
printf 'PASS: batch cleanup preserves symbolic names, paths, inodes, actions and ownership references\n'

new_case incomplete
managed One
managed Two
WEBAPP_FIND_FAIL_AT=2 monarch-webapp-remove-all > "$TMP/output"
[[ ! -e $APP_DIR/One.desktop && ! -e $APP_DIR/Two.desktop ]] || fail 'selected launchers were not removed'
[[ -f $ICON_DIR/monarch-webapp-One.png && -f $ICON_DIR/monarch-webapp-Two.png ]] || fail 'incomplete reference inventory deleted icons'
new_case unreadable
managed One
managed Two
ln -s "$TMP/missing.desktop" "$APP_DIR/Unknown.desktop"
monarch-webapp-remove-all > "$TMP/output"
[[ -f $ICON_DIR/monarch-webapp-One.png && -f $ICON_DIR/monarch-webapp-Two.png ]] || fail 'unknown symbolic launcher did not preserve icons'
printf 'PASS: incomplete or unknown reference inventories preserve all candidate icons\n'

new_case partial
managed One
managed Two
if WEBAPP_REMOVE_FAIL="$APP_DIR/Two.desktop" monarch-webapp-remove One Two > "$TMP/output"; then
  fail 'failed deletion reported success'
fi
[[ ! -e $APP_DIR/One.desktop && ! -e $ICON_DIR/monarch-webapp-One.png ]] || fail 'successful deletion was not cleaned after a later error'
[[ -f $APP_DIR/Two.desktop && -f $ICON_DIR/monarch-webapp-Two.png ]] || fail 'failed deletion lost its launcher or icon'
[[ $(wc -l < "$WEBAPP_CLEANUP_LOG/cache") == 1 ]] || fail 'partial deletion did not refresh the icon cache once'
printf 'PASS: a later removal failure still cleans completed deletions and retains failure status\n'

new_case closed-output
managed One
if monarch-webapp-remove One >&- 2> "$TMP/output-error"; then
  fail 'closed output reported success'
fi
[[ ! -e $APP_DIR/One.desktop && ! -e $ICON_DIR/monarch-webapp-One.png ]] || fail 'an output error interrupted icon cleanup'
[[ $(wc -l < "$WEBAPP_CLEANUP_LOG/cache") == 1 ]] || fail 'an output error skipped the cache refresh'
printf 'PASS: output errors cannot interrupt cleanup of completed removals\n'

new_case duplicate
managed One
managed Two "$ICON_DIR/monarch-webapp-One.png"
monarch-webapp-remove One Two > "$TMP/output"
[[ ! -e $ICON_DIR/monarch-webapp-One.png ]] || fail 'duplicate ownership left the last unreferenced icon'
[[ $(wc -l < "$WEBAPP_CLEANUP_LOG/cache") == 1 ]] || fail 'duplicate ownership refreshed the cache twice'
printf 'PASS: duplicate ownership is deduplicated during cleanup\n'

new_case intermediate
icon="$APP_DIR/icons/monarch-webapp.intermediate"
printf 'borrowed fixture\n' > "$icon"
managed Old "$icon"
sed -i "s|^Icon=.*|Icon=$icon|" "$APP_DIR/Old.desktop"
monarch-webapp-remove Old > "$TMP/output"
[[ -f $icon ]] || fail 'unreleased intermediate icon format was claimed as owned'
printf 'PASS: the unreleased icon namespace remains borrowed\n'

new_case reinstall
managed One
base64 -d > "$TMP/local.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF
monarch-webapp-install One https://example.com "$TMP/local.png"
[[ ! -e $ICON_DIR/monarch-webapp-One.png ]] || fail 'reinstallation did not clean the replaced icon'
[[ $(wc -l < "$WEBAPP_CLEANUP_LOG/cache") == 1 ]] || fail 'reinstallation refreshed the icon cache twice'
printf 'PASS: reinstallation refreshes the cache once after publication and cleanup\n'
