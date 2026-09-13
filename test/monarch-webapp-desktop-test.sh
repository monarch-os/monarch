#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin:/bin"
export WEBAPP_TEST_LOG="$TMP/argv" XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config"
unset DBUS_SESSION_BUS_ADDRESS DISPLAY WAYLAND_DISPLAY
mkdir -p "$HOME/.local/share/applications/icons" "$TMP/bin"
base64 -d > "$HOME/.local/share/applications/icons/local.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF
cat > "$TMP/bin/monarch-launch-webapp" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" > "$WEBAPP_TEST_LOG"
EOF
cp "$TMP/bin/monarch-launch-webapp" "$TMP/bin/monarch-webapp-handler-zoom"
chmod +x "$TMP/bin/"*

URL='https://example.com/a%20b?q=%u&literal=$HOME&quotes="yes"&backslash=\x&tick=`id`&glob=[a-z]*#part'
NAME='  L’atelier "web" \\ test  '
monarch-webapp-install "$NAME" "$URL" local.png
DESKTOP="$HOME/.local/share/applications/$NAME.desktop"
desktop-file-validate "$DESKTOP"
python3 - "$DESKTOP" "$NAME" "$URL" <<'PY'
import os
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gio, Gtk

app = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert app is not None
assert app.get_name() == sys.argv[2], (app.get_name(), sys.argv[2])
icon_name = app.get_string('Icon')
owned_icon = app.get_string('X-Monarch-WebApp-Icon')
assert '/' not in icon_name and not icon_name.endswith('.png')
assert owned_icon.endswith('/' + icon_name + '.png')
theme = Gtk.IconTheme.new()
theme.set_search_path([os.path.join(os.environ['HOME'], '.local/share/icons'), '/usr/share/icons'])
theme.set_custom_theme('hicolor')
icon = theme.lookup_icon(icon_name, 256, Gtk.IconLookupFlags.FORCE_SIZE)
assert icon is not None, icon_name
assert icon.get_filename() == owned_icon, (icon.get_filename(), owned_icon)
assert app.launch([], None)
PY
for (( attempt=0; attempt<300; attempt++ )); do
  [[ ! -f $WEBAPP_TEST_LOG ]] || break
  sleep 0.01
done
mapfile -d '' -t argv < "$WEBAPP_TEST_LOG"
[[ ${#argv[@]} == 1 && ${argv[0]} == "$URL" ]]
printf 'PASS: real Desktop Entry parser preserves the complete URL as one literal argument\n'
printf 'PASS: real GTK icon theme lookup resolves the installed hicolor name\n'

rm -- "$WEBAPP_TEST_LOG"
monarch-webapp-install Zoom 'https://zoom.us' local.png 'monarch-webapp-handler-zoom %u' 'x-scheme-handler/zoommtg;x-scheme-handler/zoomus;'
DESKTOP="$HOME/.local/share/applications/Zoom.desktop"
desktop-file-validate "$DESKTOP"
python3 - "$DESKTOP" <<'PY'
import sys
from gi.repository import Gio

app = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert app is not None
assert set(app.get_supported_types()) == {'x-scheme-handler/zoommtg', 'x-scheme-handler/zoomus'}
assert app.launch_uris(['zoommtg://zoom.us/join?confno=123&pwd=a%20b'], None)
PY
for (( attempt=0; attempt<300; attempt++ )); do
  [[ ! -f $WEBAPP_TEST_LOG ]] || break
  sleep 0.01
done
mapfile -d '' -t argv < "$WEBAPP_TEST_LOG"
[[ ${#argv[@]} == 1 && ${argv[0]} == 'zoommtg://zoom.us/join?confno=123&pwd=a%20b' ]]
printf 'PASS: real Desktop Entry parser preserves custom Exec field codes and MIME handlers\n'
