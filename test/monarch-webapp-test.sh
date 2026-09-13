#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin:/bin" MONARCH_PATH="$ROOT"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
unset DISPLAY WAYLAND_DISPLAY NIRI_SOCKET DBUS_SESSION_BUS_ADDRESS
mkdir -p "$HOME/.local/share/applications/icons" "$TMP/bin"
APP_DIR="$HOME/.local/share/applications"
THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
export WEBAPP_TEST_LOG="$TMP/argv" WEBAPP_CURL_LOG="$TMP/curl"
export WEBAPP_CACHE_LOG="$TMP/icon-cache" WEBAPP_CONVERT_LOG="$TMP/convert"
export WEBAPP_TEST_IMAGE="$TMP/icon.png"
IMAGE_TOOL=magick
command -v magick >/dev/null || IMAGE_TOOL=convert
base64 -d > "$WEBAPP_TEST_IMAGE" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF
cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/local.png"
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/bash
set -e
printf '%s\0' "$@" >> "$WEBAPP_CURL_LOG"
url=${!#}
printf '%s\n' "$url" >> "$WEBAPP_CURL_LOG.urls"
while (( $# )); do
  case $1 in -o|--output) output=$2; shift ;; esac
  shift
done
printf '%s\n' "$output" >> "$WEBAPP_CURL_LOG.outputs"
if [[ ${WEBAPP_CURL_FAIL_FIRST:-0} == "1" && ! -e $WEBAPP_CURL_LOG.first ]]; then
  touch "$WEBAPP_CURL_LOG.first"
  exit 22
fi
if [[ $output == */page.html ]]; then
  if [[ -n ${WEBAPP_CURL_HTML:-} ]]; then
    cp "$WEBAPP_CURL_HTML" "$output"
  else
    printf '<html><head></head></html>\n' > "$output"
  fi
  printf '%s' "${WEBAPP_CURL_EFFECTIVE_URL:-$url}"
  exit "${WEBAPP_CURL_STATUS:-${WEBAPP_CURL_HTML_STATUS:-0}}"
fi
cp "${WEBAPP_CURL_BODY:-$WEBAPP_TEST_IMAGE}" "$output"
if [[ -n ${WEBAPP_CURL_SUCCESS_URL:-} && $url != "$WEBAPP_CURL_SUCCESS_URL" ]]; then
  exit 22
fi
if [[ $url == */apple-touch-icon.png ]]; then
  exit "${WEBAPP_CURL_STATUS:-${WEBAPP_CURL_APPLE_STATUS:-0}}"
fi
exit "${WEBAPP_CURL_STATUS:-0}"
EOF
cat > "$TMP/bin/monarch-launch-webapp" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" > "$WEBAPP_TEST_LOG"
exit 98
EOF
cat > "$TMP/bin/update-desktop-database" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/gtk-update-icon-cache" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >> "$WEBAPP_CACHE_LOG"
exit "${WEBAPP_CACHE_STATUS:-0}"
EOF
cat > "$TMP/bin/prlimit" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >> "$WEBAPP_CONVERT_LOG"
exec /usr/bin/prlimit "$@"
EOF
cat > "$TMP/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
for command in "$@"; do
  [[ $command != magick || ${WEBAPP_USE_CONVERT:-0} != 1 ]] || exit 1
  command -v "$command" >/dev/null || exit 1
done
EOF
cat > "$TMP/bin/gum" <<'EOF'
#!/bin/bash
operation=$1
shift
if [[ $operation == choose ]]; then
  [[ ${WEBAPP_GUM_CANCEL_AT:-} != choose ]] || exit 130
  printf '%s' "${WEBAPP_GUM_CHOICE:-}"
  exit
fi
while (( $# )); do
  case $1 in --prompt) prompt=$2; shift ;; esac
  shift
done
[[ $prompt != "${WEBAPP_GUM_CANCEL_AT:-}> " ]] || exit 130
case $prompt in
  'Name> ') printf '%s' "${WEBAPP_GUM_NAME:-Interactive}" ;;
  'URL> ') printf '%s' "${WEBAPP_GUM_URL:-example.com}" ;;
  'Icon URL/file/name> ') printf '%s' "${WEBAPP_GUM_ICON:-https://example.com/icon.png}" ;;
  *) exit 97 ;;
esac
EOF
cat > "$TMP/bin/find" <<'EOF'
#!/bin/bash
/usr/bin/find "$@"
status=$?
exit "${WEBAPP_FIND_STATUS:-$status}"
EOF
chmod +x "$TMP/bin/"*
for command in monarch-webapp-handler-zoom monarch-pkg-add monarch-launch-browser xdg-open gtk-launch gio noctalia sudo pacman; do
  ln -s "$TMP/bin/monarch-launch-webapp" "$TMP/bin/$command"
done
source "$ROOT/install/helpers/webapps.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reject() { if "$@" > "$TMP/rejected" 2>&1; then fail "accepted: $*"; fi; }
equal() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
present() { [[ -f $1 && ! -L $1 ]] || fail "missing regular file: $1"; }
absent() { [[ ! -e $1 && ! -L $1 ]] || fail "unexpected file: $1"; }
entry() { sed -n "s/^$1=//p" "$2"; }
owned_icon() { webapp_unescape "$(entry X-Monarch-WebApp-Icon "$1")"; }
normalized_icon() {
  local desktop=$1 icon name
  icon=$(owned_icon "$desktop")
  name=$(entry Icon "$desktop")
  present "$icon"
  [[ $icon == "$THEME_ICON_DIR/monarch-webapp-"*.png ]] || fail "icon outside hicolor: $icon"
  [[ $name =~ ^monarch-webapp-[[:alnum:]]+$ ]] || fail 'invalid theme icon name'
  equal "$name.png" "${icon##*/}" 'theme name and owned path differ'
  equal "$(file --brief --mime-type -- "$icon")" image/png 'normalized MIME type'
  equal "$(identify -format '%m %wx%h' "$icon")" 'PNG 256x256' 'normalized image dimensions'
  "$IMAGE_TOOL" "$icon" null: 2>/dev/null || fail 'normalized PNG does not decode'
}
legacy() {
  mkdir -p "${1%/*}"
  printf '[Desktop Entry]\nType=Application\nName=Legacy\nExec=%s\nIcon=%s\n' \
    "${2:-monarch-launch-webapp https://example.com}" "${3:-$APP_DIR/icons/local.png}" > "$1"
}
logged_pair() {
  local log=$1 key=$2 value=$3
  local i
  local -a args=()
  mapfile -d '' -t args < "$log"
  for i in "${!args[@]}"; do
    [[ ${args[i]} != "$key" || ${args[i+1]:-} != "$value" ]] || return 0
  done
  fail "$log missing $key $value"
}
curl_pair() { logged_pair "$WEBAPP_CURL_LOG" "$1" "$2"; }
reset_curl() { : > "$WEBAPP_CURL_LOG"; : > "$WEBAPP_CURL_LOG.urls"; }

(
  export HOME="$TMP/option-home"
  mkdir -p "$HOME/.local/share/applications/-delete"
  cd "$HOME/.local/share/applications"
  printf 'unmanaged sentinel\n' > keep.desktop
  monarch-webapp-remove-all -delete > /dev/null
  present "$PWD/keep.desktop"
  equal "$(< keep.desktop)" 'unmanaged sentinel' 'relative find option escaped its scope'
)
printf 'ok - relative application subdirectory cannot become a find option\n'

monarch-webapp-install 'Benign app' example.com local.png
[[ -f $APP_DIR/Benign\ app.desktop ]] || fail 'benign install'
monarch-webapp-remove 'Benign app'
[[ ! -e $APP_DIR/Benign\ app.desktop ]] || fail 'benign removal'

printf 'outside sentinel\n' > "$HOME/.local/share/outside.desktop"
reject monarch-webapp-remove ../outside
[[ $(< "$HOME/.local/share/outside.desktop") == 'outside sentinel' ]] || fail 'removal escaped applications'
reject monarch-webapp-install ../outside https://example.com local.png
[[ $(< "$HOME/.local/share/outside.desktop") == 'outside sentinel' ]] || fail 'installation escaped applications'

for name in 'Été 東京' "L'appli d'Ana" 'Glob [ab]*?' 'Back\slash' '  Padded name  ' '-name'; do
  monarch-webapp-install "$name" example.com local.png
  present "$APP_DIR/$name.desktop"
  monarch-webapp-remove -- "$name" > /dev/null
  absent "$APP_DIR/$name.desktop"
done
for name in '' '.' '..' '   ' 'folder/name' $'line\nExec=bad' $'carriage\rreturn' $'tab\tname' $'delete\177name' $'escape\033name'; do
  reject monarch-webapp-install "$name" example.com local.png
done
reject monarch-webapp-install Traversal example.com ../../outside.desktop
present "$APP_DIR/icons/local.png"
printf 'ok - names and traversal boundaries\n'

for url in example.com 'http://example.com/path?x=1&y=2#part' 'HTTPS://example.com' 'https://[::1]:8443/path'; do
  monarch-webapp-install URL "$url" local.png
  webapp_read "$APP_DIR/URL.desktop"
  expected=$url
  [[ $url != "example.com" ]] || expected='https://example.com'
  equal "$WEBAPP_EXEC" "monarch-launch-webapp \"$expected\"" 'URL normalization'
done
url='https://example.com/a%20b?q=%U&quote="&cash=$HOME&tick=`id`&glob=[ab]&slash=\tail'
monarch-webapp-install URL "$url" local.png
webapp_read "$APP_DIR/URL.desktop"
expected='monarch-launch-webapp "https://example.com/a%%20b?q=%%U&quote=\"&cash=\$HOME&tick=\`id\`&glob=[ab]&slash=\\tail"'
equal "$WEBAPP_EXEC" "$expected" 'URL escaping and literal field codes'
monarch-webapp-install URL "https://example.com/it's" local.png
webapp_read "$APP_DIR/URL.desktop"
equal "$WEBAPP_EXEC" "monarch-launch-webapp \"https://example.com/it's\"" 'URL apostrophe'
for url in '' ' ' 'https://' 'http:///path' 'https://?query' 'https://#fragment' 'https://:443/' 'https://user@/' 'https://example.com:wrong/' 'https://example.com/with space' $'https://example.com/\nExec=bad' $'https://example.com/\tbad' 'file:///etc/passwd' 'javascript:alert(1)' 'data:text/html,test' 'ftp://example.com' 'ssh://example.com'; do
  reject monarch-webapp-install Invalid "$url" local.png
done
absent "$APP_DIR/Invalid.desktop"
printf 'ok - HTTP(S) URL validation and escaping\n'

custom='monarch-webapp-handler-zoom %u'
monarch-webapp-install Zoom https://app.zoom.us local.png "$custom" 'x-scheme-handler/zoommtg;x-scheme-handler/zoomus'
webapp_read "$APP_DIR/Zoom.desktop"
equal "$WEBAPP_EXEC" "$custom" 'custom Exec field code'
equal "$(entry MimeType "$APP_DIR/Zoom.desktop")" 'x-scheme-handler/zoommtg;x-scheme-handler/zoomus;' 'MIME terminator'
custom='sh -c "printf test; printf %s quoted" -- %U'
monarch-webapp-install Custom https://example.com local.png "$custom" 'text/plain;'
webapp_read "$APP_DIR/Custom.desktop"
equal "$WEBAPP_EXEC" "$custom" 'explicit custom command'
for invalid in $'true\nExec=bad' $'true\rName=bad' $'true\tbad' '   '; do
  reject monarch-webapp-install Rejected https://example.com local.png "$invalid"
done
for invalid in 'text/plain;;' 'text/plain;Exec=bad' 'text/plain other/plain' 'text' '/plain' 'text/' ';text/plain' $'text/plain\nExec=bad'; do
  reject monarch-webapp-install Rejected https://example.com local.png '' "$invalid"
done
absent "$APP_DIR/Rejected.desktop"
absent "$WEBAPP_TEST_LOG"
printf 'ok - custom Exec and MIME validation\n'

icon_url='https://example.com/icon[1].png?x=1&y=2'
monarch-webapp-install Download https://example.com "$icon_url"
mapfile -d '' -t curl_args < "$WEBAPP_CURL_LOG"
equal "${curl_args[0]}" '--disable' 'curl configuration disabled first'
equal "${curl_args[-2]}" '--' 'curl URL option separator'
equal "${curl_args[-1]}" "$icon_url" 'curl URL unchanged'
for flag in --fail --location --globoff; do
  found=false
  for argument in "${curl_args[@]}"; do [[ $argument != "$flag" ]] || found=true; done
  [[ $found == "true" ]] || fail "curl missing $flag"
done
curl_pair --proto '=http,https'
curl_pair --proto-redir '=http,https'
curl_pair --max-redirs 3
curl_pair --connect-timeout 5
curl_pair --max-time 15
curl_pair --max-filesize 5242880
icon=$(owned_icon "$APP_DIR/Download.desktop")
normalized_icon "$APP_DIR/Download.desktop"
equal "$(stat -c %a "$icon")" 644 'published icon permissions'
[[ -z $(find "$APP_DIR" -maxdepth 1 -name '.monarch-webapp.*' -print -quit) ]] || fail 'desktop staging leaked'
[[ -z $(find "$THEME_ICON_DIR" -name '.monarch-webapp.*' -print -quit) ]] || fail 'icon staging leaked'
url='https://example.com/path?x=1&y=2#fragment'
WEBAPP_CURL_APPLE_STATUS=22 monarch-webapp-install Favicon "$url" ''
normalized_icon "$APP_DIR/Favicon.desktop"
curl_pair --data-urlencode "domain=$url"
curl_pair --data-urlencode 'sz=256'
curl_pair -- 'https://www.google.com/s2/favicons'
curl_pair --write-out '%{url_effective}'
curl_pair --max-time 5
curl_pair --max-filesize 524288
reject monarch-webapp-install BadIcon example.com file:///etc/passwd
reject monarch-webapp-install BadIcon example.com ftp://example.com/icon.png
absent "$APP_DIR/BadIcon.desktop"
printf 'ok - download protocol restrictions and favicon query encoding\n'

cp "$APP_DIR/Download.desktop" "$TMP/old.desktop"
cp "$icon" "$TMP/old.png"
before=$(find "$HOME/.local/share" -type f -printf '%P\n' | sort)
printf '<html><body>not PNG</body></html>\n' > "$TMP/html"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$TMP/svg"
touch "$TMP/empty"
cp "$WEBAPP_TEST_IMAGE" "$TMP/oversize"
truncate -s 5242881 "$TMP/oversize"
head -c 40 "$WEBAPP_TEST_IMAGE" > "$TMP/truncated"
for body in html svg empty oversize truncated; do
  export WEBAPP_CURL_BODY="$TMP/$body"
  reject monarch-webapp-install Download https://changed.example.com 'https://example.com/new.png'
  cmp -s "$APP_DIR/Download.desktop" "$TMP/old.desktop" || fail "$body replaced launcher"
  cmp -s "$icon" "$TMP/old.png" || fail "$body replaced icon"
  equal "$(find "$HOME/.local/share" -type f -printf '%P\n' | sort)" "$before" "$body leaked staging"
done
unset WEBAPP_CURL_BODY
export WEBAPP_CURL_STATUS=22
reject monarch-webapp-install Download https://changed.example.com 'https://example.com/new.png'
cmp -s "$APP_DIR/Download.desktop" "$TMP/old.desktop" || fail 'HTTP failure replaced launcher'
cmp -s "$icon" "$TMP/old.png" || fail 'HTTP failure replaced icon'
equal "$(find "$HOME/.local/share" -type f -printf '%P\n' | sort)" "$before" 'HTTP failure leaked staging'
unset WEBAPP_CURL_STATUS
cp "$TMP/html" "$APP_DIR/icons/html.png"
cp "$TMP/oversize" "$APP_DIR/icons/large.png"
touch "$APP_DIR/icons/empty.png"
mkdir "$APP_DIR/icons/directory.png"
cp "$TMP/truncated" "$APP_DIR/icons/truncated.png"
for invalid in html.png large.png empty.png directory.png truncated.png; do
  reject monarch-webapp-install Invalid example.com "$invalid"
done
absent "$APP_DIR/Invalid.desktop"
cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/limit.png"
truncate -s 5242880 "$APP_DIR/icons/limit.png"
monarch-webapp-install Limit example.com limit.png
normalized_icon "$APP_DIR/Limit.desktop"
[[ -z $(find "$THEME_ICON_DIR" -name '.monarch-webapp.*' -print -quit) ]] || fail 'rejected image leaked icon staging'
printf 'ok - image validation, size limit, failed reinstall preservation\n'

(
  export HOME="$TMP/import-home"
  APP_DIR="$HOME/.local/share/applications"
  THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$APP_DIR/icons" "$TMP/imports"
  cp "$WEBAPP_TEST_IMAGE" "$TMP/imports/source image.png"
  "$IMAGE_TOOL" -size 48x24 xc:red "$TMP/imports/wide.jpg" 2>/dev/null
  "$IMAGE_TOOL" -size 16x40 xc:blue "$TMP/imports/tall.gif" 2>/dev/null
  for source in "$TMP/imports/source image.png" "$TMP/imports/wide.jpg" "$TMP/imports/tall.gif"; do
    cp "$source" "$TMP/import-sentinel"
    monarch-webapp-install Imported example.com "$source"
    normalized_icon "$APP_DIR/Imported.desktop"
    icon=$(owned_icon "$APP_DIR/Imported.desktop")
    cmp -s "$source" "$TMP/import-sentinel" || fail 'explicit import changed original image'
    monarch-webapp-remove Imported > /dev/null
    absent "$icon"
    cmp -s "$source" "$TMP/import-sentinel" || fail 'removal changed original image'
  done
  (
    cd "$TMP/imports"
    monarch-webapp-install Relative example.com './source image.png'
    normalized_icon "$APP_DIR/Relative.desktop"
  )
  cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/Legacy.png"
  legacy "$APP_DIR/Legacy.desktop" 'monarch-launch-webapp https://example.com' "$APP_DIR/icons/Legacy.png"
  monarch-webapp-install Legacy example.com Legacy.png
  normalized_icon "$APP_DIR/Legacy.desktop"
  icon=$(owned_icon "$APP_DIR/Legacy.desktop")
  monarch-webapp-install Legacy example.com Legacy.png
  replacement=$(owned_icon "$APP_DIR/Legacy.desktop")
  [[ $replacement != "$icon" ]] || fail 'local reinstall reused published icon identifier'
  absent "$icon"
  monarch-webapp-remove Legacy > /dev/null
  absent "$replacement"
  cmp -s "$APP_DIR/icons/Legacy.png" "$WEBAPP_TEST_IMAGE" || fail 'legacy source was consumed'
  before=$(wc -c < "$WEBAPP_CURL_LOG")
  conversions=$(wc -c < "$WEBAPP_CONVERT_LOG")
  for reference in web-browser org.gnome.Calendar HEY.png missing.png example.svg example.xpm; do
    monarch-webapp-install Themed example.com "$reference"
    expected=$reference
    case $reference in *.png|*.svg|*.xpm) expected=${reference%.*} ;; esac
    equal "$(entry Icon "$APP_DIR/Themed.desktop")" "$expected" 'theme icon name'
    equal "$(entry X-Monarch-WebApp-Icon "$APP_DIR/Themed.desktop")" '' 'theme icon claimed ownership'
    monarch-webapp-remove Themed > /dev/null
  done
  equal "$(wc -c < "$WEBAPP_CURL_LOG")" "$before" 'theme icon triggered download'
  equal "$(wc -c < "$WEBAPP_CONVERT_LOG")" "$conversions" 'theme icon triggered conversion'
  for reference in '-option' 'theme name' 'missing/path.png' $'theme\nName=bad'; do
    reject monarch-webapp-install BadTheme example.com "$reference"
  done
  ln -s "$TMP/imports/source image.png" "$TMP/imports/symbolic.png"
  reject monarch-webapp-install Symbolic example.com "$TMP/imports/symbolic.png"
  reject monarch-webapp-install Directory example.com "$TMP/imports"
  reject monarch-webapp-install InvalidImage example.com "$TMP/html"
)
printf 'ok - local images copied, legacy sources preserved, theme names passed through\n'

(
  export HOME="$TMP/converter-home"
  APP_DIR="$HOME/.local/share/applications"
  THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$HOME"
  WEBAPP_USE_CONVERT=1 monarch-webapp-install Convert example.com "$WEBAPP_TEST_IMAGE"
  normalized_icon "$APP_DIR/Convert.desktop"
  logged_pair "$WEBAPP_CONVERT_LOG" -- convert
  logged_pair "$WEBAPP_CONVERT_LOG" -limit thread
  logged_pair "$WEBAPP_CONVERT_LOG" memory 64MiB
  logged_pair "$WEBAPP_CONVERT_LOG" map 0
  logged_pair "$WEBAPP_CONVERT_LOG" disk 0
  logged_pair "$WEBAPP_CONVERT_LOG" width 8192
  logged_pair "$WEBAPP_CONVERT_LOG" height 8192
  mapfile -d '' -t args < "$WEBAPP_CONVERT_LOG"
  for limit in --core=0 --fsize=5242880 --cpu=8 --as=536870912; do
    found=false
    for argument in "${args[@]}"; do [[ $argument != "$limit" ]] || found=true; done
    [[ $found == true ]] || fail "missing conversion resource limit $limit"
  done
  WEBAPP_CACHE_STATUS=1 monarch-webapp-install CacheFailure example.com "$WEBAPP_TEST_IMAGE"
  normalized_icon "$APP_DIR/CacheFailure.desktop"
  logged_pair "$WEBAPP_CACHE_LOG" --force --ignore-theme-index
  before=$(wc -c < "$WEBAPP_CACHE_LOG")
  ln -s "$TMP/cache-target" "$HOME/.local/share/icons/hicolor/icon-theme.cache"
  printf 'cache sentinel\n' > "$TMP/cache-target"
  monarch-webapp-install CacheSymlink example.com "$WEBAPP_TEST_IMAGE"
  equal "$(wc -c < "$WEBAPP_CACHE_LOG")" "$before" 'cache tool followed a symbolic cache file'
  equal "$(< "$TMP/cache-target")" 'cache sentinel' 'symbolic cache target changed'
)
printf 'ok - converter fallback, resource limits, and safe optional icon-cache refresh\n'

(
  export HOME="$TMP/auto-home"
  APP_DIR="$HOME/.local/share/applications"
  THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$HOME"
  export WEBAPP_CURL_HTML="$TMP/page.html"
  export WEBAPP_CURL_EFFECTIVE_URL='https://redirect.example.net/app/page.html'
  cat > "$WEBAPP_CURL_HTML" <<'EOF'
<html><head>
<link rel="icon" href="first.png">
<link rel="icon" href="second.png">
<link rel="icon" href="third.png">
<link rel="icon" href="fourth.png">
</head></html>
EOF
  page='https://original.example.com/path?x=1&y=2#fragment'
  first='https://redirect.example.net/app/first.png'
  second='https://redirect.example.net/app/second.png'
  third='https://redirect.example.net/app/third.png'
  apple='https://redirect.example.net/apple-touch-icon.png'
  google='https://www.google.com/s2/favicons'
  reset_curl
  WEBAPP_CURL_SUCCESS_URL="$third" monarch-webapp-install Third "$page" ''
  normalized_icon "$APP_DIR/Third.desktop"
  equal "$(< "$WEBAPP_CURL_LOG.urls")" "$(printf '%s\n' "$page" "$first" "$second" "$third")" 'HTML candidate order and effective URL'
  reset_curl
  WEBAPP_CURL_SUCCESS_URL="$apple" monarch-webapp-install Apple "$page" ''
  normalized_icon "$APP_DIR/Apple.desktop"
  equal "$(< "$WEBAPP_CURL_LOG.urls")" "$(printf '%s\n' "$page" "$first" "$second" "$third" "$apple")" 'three-candidate limit and apple fallback'
  reset_curl
  WEBAPP_CURL_SUCCESS_URL="$google" monarch-webapp-install Google "$page" ''
  normalized_icon "$APP_DIR/Google.desktop"
  equal "$(< "$WEBAPP_CURL_LOG.urls")" "$(printf '%s\n' "$page" "$first" "$second" "$third" "$apple" "$google")" 'Google fallback order'
  curl_pair --data-urlencode "domain=$page"
  curl_pair --data-urlencode 'sz=256'
  reset_curl
  WEBAPP_CURL_HTML_STATUS=22 monarch-webapp-install FailedPage "$page" ''
  normalized_icon "$APP_DIR/FailedPage.desktop"
  equal "$(< "$WEBAPP_CURL_LOG.urls")" "$(printf '%s\n' "$page" 'https://original.example.com/apple-touch-icon.png')" 'failed HTML used original origin'
  reset_curl
  WEBAPP_CURL_EFFECTIVE_URL='file:///tmp/icon.png' monarch-webapp-install InvalidRedirect "$page" ''
  equal "$(< "$WEBAPP_CURL_LOG.urls")" "$(printf '%s\n' "$page" 'https://original.example.com/apple-touch-icon.png')" 'invalid effective URL was not used'
  reset_curl
  WEBAPP_CURL_STATUS=22 reject monarch-webapp-install Offline "$page" ''
  absent "$APP_DIR/Offline.desktop"
  [[ -z $(find "$THEME_ICON_DIR" -name '.monarch-webapp.*' -print -quit) ]] || fail 'automatic failure leaked staging'
  before=$(wc -c < "$WEBAPP_CURL_LOG")
  conversions=$(wc -c < "$WEBAPP_CONVERT_LOG")
  WEBAPP_FETCH_DEADLINE=$((SECONDS - 1)) reject webapp_download "$TMP/expired" "$page" 524288 5
  WEBAPP_FETCH_DEADLINE=$((SECONDS - 1)) reject webapp_convert_icon "$WEBAPP_TEST_IMAGE" "$TMP/expired.png"
  equal "$(wc -c < "$WEBAPP_CURL_LOG")" "$before" 'download started after automatic deadline'
  equal "$(wc -c < "$WEBAPP_CONVERT_LOG")" "$conversions" 'conversion started after automatic deadline'
  duration=$(WEBAPP_FETCH_DEADLINE=$((SECONDS + 2)) webapp_timeout 15)
  (( duration > 0 && duration <= 2 )) || fail 'request timeout exceeded remaining automatic budget'
)
printf 'ok - automatic candidate order, redirected origin, fallbacks, and deadline\n'

legacy "$TMP/symlink-target.desktop"
cp "$TMP/symlink-target.desktop" "$TMP/sentinel.desktop"
ln -s "$TMP/symlink-target.desktop" "$APP_DIR/Link.desktop"
reject monarch-webapp-install Link example.com local.png
reject monarch-webapp-remove Link
cmp -s "$TMP/symlink-target.desktop" "$TMP/sentinel.desktop" || fail 'symbolic launcher target changed'
ln -s "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/link.png"
reject monarch-webapp-install IconLink example.com link.png
absent "$APP_DIR/IconLink.desktop"
mkdir "$APP_DIR/Directory.desktop"
reject monarch-webapp-install Directory example.com local.png
legacy "$APP_DIR/Unmanaged.desktop" 'other-browser https://example.com'
cp "$APP_DIR/Unmanaged.desktop" "$TMP/unmanaged.desktop"
reject monarch-webapp-install Unmanaged example.com local.png
cmp -s "$APP_DIR/Unmanaged.desktop" "$TMP/unmanaged.desktop" || fail 'installation replaced unmanaged launcher'
for relative in .local .local/share .local/share/applications .local/share/applications/icons \
  .local/share/icons .local/share/icons/hicolor .local/share/icons/hicolor/256x256 \
  .local/share/icons/hicolor/256x256/apps; do
  unsafe_home="$TMP/unsafe-${relative//\//-}"
  target="$TMP/outside-${relative//\//-}"
  mkdir -p "$(dirname "$unsafe_home/$relative")" "$target"
  ln -s "$target" "$unsafe_home/$relative"
  printf 'untouched\n' > "$target/sentinel"
  reject env HOME="$unsafe_home" monarch-webapp-install Unsafe example.com 'https://example.com/icon.png'
  reject env HOME="$unsafe_home" monarch-webapp-remove --check
  reject env HOME="$unsafe_home" monarch-webapp-remove-all
  equal "$(find "$target" -type f -printf '%f\n')" sentinel "followed symbolic ancestor $relative"
done
printf 'ok - symbolic launcher, icon, and directory ancestors\n'

monarch-webapp-remove-all > /dev/null
[[ -L $APP_DIR/Link.desktop ]] || fail 'bulk removal deleted symbolic launcher'
cmp -s "$TMP/symlink-target.desktop" "$TMP/sentinel.desktop" || fail 'bulk removal followed symbolic launcher'
legacy "$APP_DIR/nested/deeper/Legacy.desktop"
legacy "$APP_DIR/Zoom.desktop" 'monarch-webapp-handler-zoom %u'
legacy "$APP_DIR/Quoted.desktop" '"monarch-launch-webapp" "https://example.com"'
legacy "$APP_DIR/Marked.desktop" 'custom-browser https://example.com'
printf 'X-Monarch-WebApp=true\n' >> "$APP_DIR/Marked.desktop"
legacy "$APP_DIR/Argument.desktop" 'printf monarch-launch-webapp'
legacy "$APP_DIR/Prefix.desktop" 'monarch-launch-webapp-imposter https://example.com'
legacy "$APP_DIR/Comment.desktop" 'other-browser https://example.com'
printf '# Exec=monarch-launch-webapp https://example.com\n' >> "$APP_DIR/Comment.desktop"
legacy "$APP_DIR/False.desktop" 'custom-browser https://example.com'
printf 'X-Monarch-WebApp=false\n' >> "$APP_DIR/False.desktop"
legacy "$APP_DIR/OtherSection.desktop" 'other-browser https://example.com'
printf '[Desktop Action Open]\nExec=monarch-launch-webapp https://example.com\nX-Monarch-WebApp=true\n' >> "$APP_DIR/OtherSection.desktop"
printf 'Exec=monarch-launch-webapp https://example.com\nX-Monarch-WebApp=true\n[Desktop Entry]\nType=Application\nExec=other-browser\n' > "$APP_DIR/BeforeSection.desktop"
legacy "$APP_DIR/Duplicate.desktop"
printf 'Exec=other-browser\n' >> "$APP_DIR/Duplicate.desktop"
legacy "$APP_DIR/NotApplication.desktop"
printf 'Type=Link\n' >> "$APP_DIR/NotApplication.desktop"
monarch-webapp-remove --check
monarch-webapp-remove Legacy > /dev/null
absent "$APP_DIR/nested/deeper/Legacy.desktop"
monarch-webapp-remove-all > /dev/null
for name in Zoom Quoted Marked; do absent "$APP_DIR/$name.desktop"; done
for name in Argument Prefix Comment False OtherSection BeforeSection Duplicate NotApplication; do present "$APP_DIR/$name.desktop"; done
reject monarch-webapp-remove --check
present "$APP_DIR/icons/local.png"
printf 'ok - nested legacy launchers and exact ownership markers\n'

legacy "$APP_DIR/one/Same.desktop"
legacy "$APP_DIR/two/Same.desktop"
legacy "$APP_DIR/Unique.desktop"
reject monarch-webapp-remove Same
present "$APP_DIR/one/Same.desktop"
present "$APP_DIR/two/Same.desktop"
reject monarch-webapp-remove Unique Missing
present "$APP_DIR/Unique.desktop"
monarch-webapp-remove Unique Unique > /dev/null
absent "$APP_DIR/Unique.desktop"
monarch-webapp-remove-all > /dev/null
absent "$APP_DIR/one/Same.desktop"
absent "$APP_DIR/two/Same.desktop"
reject monarch-webapp-remove --check
monarch-webapp-install --check example.com local.png
monarch-webapp-install --all example.com local.png
monarch-webapp-remove --check
present "$APP_DIR/--check.desktop"
reject monarch-webapp-remove --check extra
monarch-webapp-remove -- --check > /dev/null
absent "$APP_DIR/--check.desktop"
present "$APP_DIR/--all.desktop"
monarch-webapp-remove -- --all > /dev/null
reject monarch-webapp-remove --check
printf 'ok - ambiguous names, atomic selection, --check and option-like names\n'

legacy "$TMP/outside/Outside.desktop"
legacy "$APP_DIR/inside/Selected.desktop"
legacy "$APP_DIR/Keep.desktop"
ln -s "$TMP/outside" "$APP_DIR/linked"
reject monarch-webapp-remove-all "$TMP/outside"
reject monarch-webapp-remove-all "$APP_DIR/.."
reject monarch-webapp-remove-all "$APP_DIR/linked"
monarch-webapp-remove-all "$APP_DIR/inside" > /dev/null
absent "$APP_DIR/inside/Selected.desktop"
present "$APP_DIR/Keep.desktop"
before=$(find "$APP_DIR" -type f -printf '%P\n' | sort)
reject env WEBAPP_FIND_STATUS=1 monarch-webapp-remove-all
reject env WEBAPP_FIND_STATUS=1 monarch-webapp-remove Keep
equal "$(find "$APP_DIR" -type f -printf '%P\n' | sort)" "$before" 'failed inventory removed launchers'
monarch-webapp-remove-all > /dev/null
absent "$APP_DIR/Keep.desktop"
present "$TMP/outside/Outside.desktop"
[[ -L $APP_DIR/linked ]] || fail 'bulk removal touched linked directory'
printf 'ok - bulk removal scope and failed inventory preservation\n'

(
  export HOME="$TMP/ownership-home"
  APP_DIR="$HOME/.local/share/applications"
  THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$APP_DIR/icons"
  cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/local.png"
  monarch-webapp-install Borrowed example.com local.png
  normalized_icon "$APP_DIR/Borrowed.desktop"
  icon=$(owned_icon "$APP_DIR/Borrowed.desktop")
  cmp -s "$APP_DIR/icons/local.png" "$WEBAPP_TEST_IMAGE" || fail 'legacy import changed source'
  monarch-webapp-remove Borrowed > /dev/null
  absent "$icon"
  present "$APP_DIR/icons/local.png"
  cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/Legacy.png"
  legacy "$APP_DIR/Legacy.desktop" 'monarch-launch-webapp https://example.com' "$APP_DIR/icons/Legacy.png"
  monarch-webapp-remove Legacy > /dev/null
  present "$APP_DIR/icons/Legacy.png"
  monarch-webapp-install Owned example.com 'https://example.com/icon.png'
  icon=$(owned_icon "$APP_DIR/Owned.desktop")
  monarch-webapp-install Owned example.com 'https://example.com/replacement.png'
  replacement=$(owned_icon "$APP_DIR/Owned.desktop")
  [[ $replacement != "$icon" ]] || fail 'replacement reused previous icon download target'
  absent "$icon"
  monarch-webapp-remove Owned > /dev/null
  absent "$replacement"
  monarch-webapp-install Shared example.com 'https://example.com/shared.png'
  icon=$(owned_icon "$APP_DIR/Shared.desktop")
  legacy "$APP_DIR/Unmanaged.desktop" other-browser "$icon"
  monarch-webapp-remove Shared > /dev/null
  present "$icon"
  present "$APP_DIR/Unmanaged.desktop"
  for reference in name normalized symlink hardlink action; do
    monarch-webapp-install Alias example.com 'https://example.com/shared.png'
    icon=$(owned_icon "$APP_DIR/Alias.desktop")
    case $reference in
      name) legacy "$APP_DIR/AliasReference.desktop" other-browser "$(entry Icon "$APP_DIR/Alias.desktop")" ;;
      normalized) legacy "$APP_DIR/AliasReference.desktop" other-browser "$THEME_ICON_DIR/../apps/${icon##*/}" ;;
      symlink)
        ln -s "$icon" "$APP_DIR/icons/alias.png"
        legacy "$APP_DIR/AliasReference.desktop" other-browser "$APP_DIR/icons/alias.png"
        ;;
      hardlink)
        ln "$icon" "$APP_DIR/icons/hardlink.png"
        legacy "$APP_DIR/AliasReference.desktop" other-browser "$APP_DIR/icons/hardlink.png"
        ;;
      action)
        legacy "$APP_DIR/AliasReference.desktop" other-browser
        printf '[Desktop Action Shared]\nName=Shared\nIcon=%s\nExec=other-browser\n' "$icon" >> "$APP_DIR/AliasReference.desktop"
        ;;
    esac
    monarch-webapp-remove Alias > /dev/null
    present "$icon"
    rm -- "$APP_DIR/AliasReference.desktop"
  done
  monarch-webapp-install LinkIcon example.com 'https://example.com/icon.png'
  icon=$(owned_icon "$APP_DIR/LinkIcon.desktop")
  cp "$icon" "$TMP/owned-sentinel.png"
  mv "$icon" "$TMP/owned-target.png"
  ln -s "$TMP/owned-target.png" "$icon"
  monarch-webapp-remove LinkIcon > /dev/null
  absent "$APP_DIR/LinkIcon.desktop"
  [[ -L $icon ]] || fail 'owned icon cleanup removed a symlink'
  cmp -s "$TMP/owned-target.png" "$TMP/owned-sentinel.png" || fail 'owned symbolic icon target changed'
)
printf 'ok - borrowed, owned, shared and symbolic icon cleanup\n'

(
  export HOME="$TMP/interactive-home"
  APP_DIR="$HOME/.local/share/applications"
  mkdir -p "$APP_DIR/icons"
  cp "$WEBAPP_TEST_IMAGE" "$APP_DIR/icons/local.png"
  before=$(wc -c < "$WEBAPP_CURL_LOG")
  for stage in Name URL; do
    export WEBAPP_GUM_CANCEL_AT=$stage
    reject monarch-webapp-install
    [[ -z $(find "$APP_DIR" -name '*.desktop' -print -quit) ]] || fail 'cancelled input created launcher'
    equal "$(wc -c < "$WEBAPP_CURL_LOG")" "$before" 'cancelled input downloaded icon'
  done
  export WEBAPP_GUM_CANCEL_AT='Icon URL/file/name' WEBAPP_CURL_STATUS=22
  reject monarch-webapp-install
  [[ -z $(find "$APP_DIR" -name '*.desktop' -print -quit) ]] || fail 'cancelled icon prompt created launcher'
  [[ -z $(find "$HOME/.local/share" -name '.monarch-webapp.*' -print -quit) ]] || fail 'cancelled icon prompt leaked staging'
  unset WEBAPP_GUM_CANCEL_AT WEBAPP_CURL_STATUS
  WEBAPP_CURL_STATUS=22 WEBAPP_GUM_NAME=ManualTheme WEBAPP_GUM_ICON=org.gnome.Calendar \
    monarch-webapp-install > /dev/null
  equal "$(entry Icon "$APP_DIR/ManualTheme.desktop")" org.gnome.Calendar 'manual theme fallback'
  equal "$(entry X-Monarch-WebApp-Icon "$APP_DIR/ManualTheme.desktop")" '' 'manual theme claimed ownership'
  WEBAPP_CURL_STATUS=22 WEBAPP_GUM_NAME=ManualLocal WEBAPP_GUM_ICON=local.png \
    monarch-webapp-install > /dev/null
  THEME_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  normalized_icon "$APP_DIR/ManualLocal.desktop"
  present "$APP_DIR/icons/local.png"
  monarch-webapp-install Keep example.com local.png
  export WEBAPP_GUM_CANCEL_AT=choose
  reject monarch-webapp-remove
  present "$APP_DIR/Keep.desktop"
  unset WEBAPP_GUM_CANCEL_AT
  export WEBAPP_GUM_CHOICE=''
  reject monarch-webapp-remove
  present "$APP_DIR/Keep.desktop"
  export WEBAPP_GUM_NAME="L'appli interactive" WEBAPP_CURL_FAIL_FIRST=1
  monarch-webapp-install > /dev/null
  present "$APP_DIR/L'appli interactive.desktop"
  export WEBAPP_GUM_CHOICE="L'appli interactive"
  monarch-webapp-remove > /dev/null
  absent "$APP_DIR/L'appli interactive.desktop"
  present "$APP_DIR/Keep.desktop"
)
absent "$WEBAPP_TEST_LOG"
printf 'ok - interactive cancellation, favicon fallback, and selection\n'
printf 'PASS: webapp boundaries\n'
