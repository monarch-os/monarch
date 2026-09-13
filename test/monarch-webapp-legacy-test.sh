#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WEBAPP_TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$WEBAPP_TEST_TMP"' EXIT
WEBAPP_TEST_HOME="$WEBAPP_TEST_TMP/home"
APP_DIR="$WEBAPP_TEST_HOME/.local/share/applications"
ICON="$WEBAPP_TEST_TMP/source.png"
CUSTOM_EXEC='custom-browser --new-window https://example.com'
mkdir -p "$APP_DIR" "$WEBAPP_TEST_TMP/bin"
base64 -d > "$ICON" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF
cp -- "$ICON" "$WEBAPP_TEST_TMP/original.png"
printf '#!/bin/bash\nexit 0\n' > "$WEBAPP_TEST_TMP/bin/gtk-update-icon-cache"
chmod +x "$WEBAPP_TEST_TMP/bin/gtk-update-icon-cache"
printf '[Desktop Entry]\nType=Application\nName=Legacy custom\nExec=%s\nIcon=%s\n' \
  "$CUSTOM_EXEC" "$ICON" > "$APP_DIR/Legacy custom.desktop"
cp -- "$APP_DIR/Legacy custom.desktop" "$WEBAPP_TEST_TMP/original.desktop"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_webapp() {
  env -u DISPLAY -u WAYLAND_DISPLAY -u NIRI_SOCKET -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$WEBAPP_TEST_HOME" PATH="$WEBAPP_TEST_TMP/bin:$ROOT/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$WEBAPP_TEST_HOME/.config" XDG_DATA_HOME="$WEBAPP_TEST_HOME/.local/share" \
    XDG_CACHE_HOME="$WEBAPP_TEST_HOME/.cache" XDG_STATE_HOME="$WEBAPP_TEST_HOME/.local/state" \
    "$@"
}
legacy_unchanged() {
  cmp -s "$APP_DIR/Legacy custom.desktop" "$WEBAPP_TEST_TMP/original.desktop" || fail 'legacy custom launcher changed'
  cmp -s "$ICON" "$WEBAPP_TEST_TMP/original.png" || fail 'source icon changed'
}

if run_webapp monarch-webapp-install 'Legacy custom' example.com "$ICON" "$CUSTOM_EXEC" \
  > "$WEBAPP_TEST_TMP/rejected" 2>&1; then
  fail 'replaced an unmarked custom launcher'
fi
legacy_unchanged
grep -Fq 'different name' "$WEBAPP_TEST_TMP/rejected" || fail 'refusal does not explain how to recreate under another name'
if run_webapp monarch-webapp-remove --check; then
  fail 'adopted an unmarked custom launcher'
fi
printf 'ok - legacy custom launchers remain unchanged with guidance to use another name\n'

run_webapp monarch-webapp-install 'Recreated custom' example.com "$ICON" "$CUSTOM_EXEC"
grep -Fxq 'X-Monarch-WebApp=true' "$APP_DIR/Recreated custom.desktop" || fail 'custom replacement has no management marker'
grep -Fxq 'Exec=custom-browser\s--new-window\shttps://example.com' "$APP_DIR/Recreated custom.desktop" || fail 'custom command changed'
run_webapp monarch-webapp-remove --check || fail 'custom replacement is not managed'
legacy_unchanged
run_webapp monarch-webapp-remove 'Recreated custom' > /dev/null
[[ ! -e $APP_DIR/Recreated\ custom.desktop ]] || fail 'managed custom replacement was not removed'
legacy_unchanged
printf 'ok - recreating under another name manages the custom launcher and preserves its source icon\n'
