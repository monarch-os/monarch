webapp_error() {
  printf 'Error: %s\n' "$*" >&2
  return 1
}

webapp_name_valid() {
  [[ -n $1 && $1 != "." && $1 != ".." && $1 != */* && ! $1 =~ [[:cntrl:]] && $1 =~ [^[:space:]] ]]
}

webapp_url() {
  local url=$1 authority host
  [[ -n $url && ! $url =~ [[:space:][:cntrl:]] ]] || return 1
  [[ $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]] || url="https://$url"
  [[ ${url,,} == http://* || ${url,,} == https://* ]] || return 1
  authority=${url#*://}
  authority=${authority%%[/?#]*}
  host=${authority##*@}
  [[ $host =~ ^(\[[[:xdigit:]:.]+\]|[[:alnum:]_-][[:alnum:]_.-]*)(:[0-9]+)?$ ]] || return 1
  printf '%s' "$url"
}

webapp_paths() {
  local base part path
  base=$(realpath -e -- "$HOME") || return 1
  [[ $base != "/" ]] || return 1
  for part in .local .local/share .local/share/applications .local/share/applications/icons \
    .local/share/icons .local/share/icons/hicolor .local/share/icons/hicolor/256x256 \
    .local/share/icons/hicolor/256x256/apps; do
    path="$base/$part"
    [[ ! -L $path && ( ! -e $path || -d $path ) ]] ||
      { webapp_error "Unsafe application directory: $path"; return 1; }
  done
  WEBAPP_DIR="$base/.local/share/applications"
  WEBAPP_ICON_DIR="$WEBAPP_DIR/icons"
  WEBAPP_THEME_DIR="$base/.local/share/icons/hicolor"
  WEBAPP_THEME_ICON_DIR="$WEBAPP_THEME_DIR/256x256/apps"
}

webapp_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  value=${value// /\\s}
  printf '%s' "$value"
}

webapp_unescape() {
  local value=$1 char result="" i
  for (( i=0; i<${#value}; i++ )); do
    char=${value:i:1}
    if [[ $char == '\' ]]; then
      (( i+=1 ))
      case ${value:i:1} in
        s) char=' ' ;;
        n) char=$'\n' ;;
        r) char=$'\r' ;;
        t) char=$'\t' ;;
        \\) char='\' ;;
        *) return 1 ;;
      esac
    fi
    result+=$char
  done
  printf '%s' "$result"
}

webapp_exec_arg() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\`/\\\`}
  value=${value//\$/\\\$}
  value=${value//%/%%}
  printf '"%s"' "$value"
}

webapp_read() {
  local path=$1 line section="" key value
  local -A seen=()
  WEBAPP_EXEC="" WEBAPP_ICON="" WEBAPP_OWNED_ICON="" WEBAPP_MARKER="" WEBAPP_TYPE=""
  [[ -f $path && ! -L $path ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line == '['*']' ]]; then
      section=$line
      continue
    fi
    [[ $section == "[Desktop Entry]" && $line == *=* ]] || continue
    key=${line%%=*}
    case $key in
      Exec|Icon|Type|X-Monarch-WebApp|X-Monarch-WebApp-Icon)
        [[ ! ${seen[$key]+present} ]] || return 1
        seen[$key]=1
        value=$(webapp_unescape "${line#*=}") || return 1
        case $key in
          Exec) WEBAPP_EXEC=$value ;;
          Icon) WEBAPP_ICON=$value ;;
          Type) WEBAPP_TYPE=$value ;;
          X-Monarch-WebApp) WEBAPP_MARKER=$value ;;
          X-Monarch-WebApp-Icon) WEBAPP_OWNED_ICON=$value ;;
        esac
        ;;
    esac
  done < "$path"
}

webapp_is_managed() {
  [[ $WEBAPP_TYPE == "Application" && -n $WEBAPP_EXEC ]] || return 1
  [[ $WEBAPP_MARKER == "true" ]] && return 0
  [[ $WEBAPP_EXEC =~ ^(monarch-launch-webapp|monarch-webapp-handler-zoom)([[:space:]]|$) ||
    $WEBAPP_EXEC =~ ^\"(monarch-launch-webapp|monarch-webapp-handler-zoom)\"([[:space:]]|$) ]]
}

webapp_index() {
  local directory=${1:-$WEBAPP_DIR} path name resolved
  local -a paths=()
  WEBAPP_FILES=() WEBAPP_NAMES=()
  [[ -e $directory || -L $directory ]] || return 0
  resolved=$(realpath -e -- "$directory") || return 1
  [[ -d $directory && ! -L $directory && ( $resolved == "$WEBAPP_DIR" || $resolved == "$WEBAPP_DIR/"* ) ]] ||
    { webapp_error "Webapps must be inside $WEBAPP_DIR"; return 1; }
  mapfile -d '' -t paths < <(set -o pipefail; find "$resolved" -type f -name '*.desktop' -print0 | sort -z)
  wait "$!" || return 1
  for path in "${paths[@]}"; do
    name=${path##*/}
    name=${name%.desktop}
    webapp_name_valid "$name" || continue
    webapp_read "$path" && webapp_is_managed || continue
    WEBAPP_FILES+=("$path") WEBAPP_NAMES+=("$name")
  done
}

webapp_cleanup_icons() {
  local icon path line reference name identity status=0
  local -a paths=()
  local -A owned=() references=() identities=()
  for icon in "$@"; do
    webapp_owned_icon_valid "$icon" || continue
    [[ -f $icon && ! -L $icon ]] || continue
    identity=$(stat -Lc '%d:%i' -- "$icon") || return 0
    owned["$icon"]=$identity
  done
  (( ${#owned[@]} )) || return 0

  mapfile -d '' -t paths < <(find "$WEBAPP_DIR" -name '*.desktop' -print0)
  wait "$!" || return 0
  for path in "${paths[@]}"; do
    [[ -f $path && ! -L $path && -r $path ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}
      [[ $line =~ ^[[:blank:]]*(Icon|X-Monarch-WebApp-Icon)[[:blank:]]*=[[:blank:]]*(.*)$ ]] || continue
      reference=$(webapp_unescape "${BASH_REMATCH[2]}") || return 0
      [[ -n $reference ]] || continue
      references["$reference"]=1
      if [[ -e $reference ]]; then
        identity=$(stat -Lc '%d:%i' -- "$reference") || return 0
        identities["$identity"]=1
      fi
    done < "$path" || return 0
  done

  for icon in "${!owned[@]}"; do
    name=${icon##*/}
    identity=${owned[$icon]}
    [[ ! ${references[$icon]+present} && ! ${references[${name%.png}]+present} && ! ${identities[$identity]+present} ]] || continue
    [[ -f $icon && ! -L $icon ]] || continue
    [[ $(stat -Lc '%d:%i' -- "$icon") == "$identity" ]] || continue
    rm -f -- "$icon" || status=1
  done
  return "$status"
}

webapp_owned_icon_valid() {
  local icon=$1
  [[ ${icon%/*} == "$WEBAPP_THEME_ICON_DIR" && ${icon##*/} =~ ^monarch-webapp-[a-zA-Z0-9]+\.png$ ]]
}

webapp_recorded_icon() {
  local name=${WEBAPP_OWNED_ICON##*/}
  [[ $WEBAPP_MARKER == "true" ]] && webapp_owned_icon_valid "$WEBAPP_OWNED_ICON" || return 1
  if [[ $WEBAPP_ICON == "$WEBAPP_OWNED_ICON" || $WEBAPP_ICON == "${name%.png}" ]]; then
    printf '%s' "$WEBAPP_OWNED_ICON"
  else
    return 1
  fi
}

webapp_refresh_icon_cache() {
  local path
  for path in "$WEBAPP_THEME_DIR/icon-theme.cache" "$WEBAPP_THEME_DIR/.icon-theme.cache" "$WEBAPP_THEME_DIR/index.theme"; do
    [[ ! -L $path && ( ! -e $path || -f $path ) ]] || return 0
  done
  if [[ -d $WEBAPP_THEME_DIR ]] && monarch-cmd-present gtk-update-icon-cache; then
    timeout 5s gtk-update-icon-cache --force --ignore-theme-index "$WEBAPP_THEME_DIR" >/dev/null 2>&1 || true
  fi
}

webapp_remove_files() {
  local path icon status=0
  local -a icons=() removed=()
  for path in "$@"; do
    if ! webapp_read "$path" || ! webapp_is_managed; then
      webapp_error "Webapp changed: $path" || true
      status=1
      break
    fi
    icon=$(webapp_recorded_icon) || icon=""
    if ! rm -- "$path"; then
      status=1
      break
    fi
    [[ -z $icon ]] || icons+=("$icon")
    removed+=("${path##*/}")
  done
  if (( ${#icons[@]} )); then
    webapp_cleanup_icons "${icons[@]}" || status=1
    webapp_refresh_icon_cache
  fi
  if (( ${#removed[@]} )); then
    printf 'Removed %s\n' "${removed[@]}" || status=1
  fi
  return "$status"
}

webapp_image_coder() {
  local path=$1 size mime coder
  [[ -f $path && ! -L $path ]] || return 1
  size=$(stat -c %s -- "$path") || return 1
  (( size > 0 && size <= 5242880 )) || return 1
  mime=$(file --brief --mime-type -- "$path") || return 1
  case $mime in
    image/png) coder=PNG ;;
    image/jpeg) coder=JPEG ;;
    image/gif) coder=GIF ;;
    image/webp) coder=WEBP ;;
    image/bmp) coder=BMP ;;
    image/x-icon|image/vnd.microsoft.icon) coder=ICO ;;
    *) return 1 ;;
  esac
  printf '%s' "$coder"
}

webapp_timeout() {
  local duration=$1 remaining
  if [[ -n ${WEBAPP_FETCH_DEADLINE:-} ]]; then
    remaining=$((WEBAPP_FETCH_DEADLINE - SECONDS))
    (( remaining > 0 )) || return 1
    (( duration <= remaining )) || duration=$remaining
  fi
  printf '%s' "$duration"
}

webapp_download() {
  local destination=$1 url=$2 size=$3 duration
  duration=$(webapp_timeout "$4") || return 1
  shift 4
  curl --disable --fail --silent --show-error --location --globoff \
    --proto '=http,https' --proto-redir '=http,https' --max-redirs 3 --connect-timeout 5 --max-time "$duration" \
    --max-filesize "$size" --output "$destination" "$@" -- "$url"
}

webapp_convert_icon() {
  local source=$1 destination=$2 converter=magick coder duration
  coder=$(webapp_image_coder "$source") || return 1
  monarch-cmd-present magick || converter=convert
  duration=$(webapp_timeout 10) || return 1
  timeout "${duration}s" prlimit --core=0 --fsize=5242880 --cpu=8 --as=536870912 -- \
    "$converter" -limit thread 1 -limit memory 64MiB -limit map 0 -limit disk 0 \
    -limit width 8192 -limit height 8192 "$coder:${source}[0]" \
    -thumbnail 256x256 -background none -gravity center -extent 256x256 -strip "PNG:$destination" \
    >/dev/null 2>&1 && webapp_image_coder "$destination" >/dev/null
}

webapp_download_icon() {
  local directory=$1 url=$2
  shift 2
  webapp_download "$directory/source" "$url" 5242880 15 "$@" &&
    webapp_convert_icon "$directory/source" "$directory/icon.png"
}

webapp_icon_reference() {
  local reference=$1 name
  WEBAPP_ICON_KIND=auto WEBAPP_ICON_SOURCE=""
  [[ -n $reference ]] || return 0
  if [[ $reference =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
    WEBAPP_ICON_SOURCE=$(webapp_url "$reference") || return 1
    WEBAPP_ICON_KIND=download
  elif [[ $reference != */* && ( -e $WEBAPP_ICON_DIR/$reference || -L $WEBAPP_ICON_DIR/$reference ) ]]; then
    webapp_image_coder "$WEBAPP_ICON_DIR/$reference" >/dev/null || return 1
    WEBAPP_ICON_KIND=local WEBAPP_ICON_SOURCE="$WEBAPP_ICON_DIR/$reference"
  elif [[ -e $reference || -L $reference ]]; then
    webapp_image_coder "$reference" >/dev/null || return 1
    WEBAPP_ICON_SOURCE=$(realpath -e -- "$reference") || return 1
    WEBAPP_ICON_KIND=local
  else
    name=$reference
    case ${name,,} in *.png|*.svg|*.xpm) name=${name%.*} ;; esac
    [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || return 1
    WEBAPP_ICON_KIND=theme WEBAPP_ICON_SOURCE=$name
  fi
}

webapp_fetch_site_icon() {
  local directory=$1 site_url=$2 effective_url authority origin candidate candidates
  local deadline=$((SECONDS + 30))
  local WEBAPP_FETCH_DEADLINE=$((deadline - 10))
  effective_url=$(webapp_download "$directory/page.html" "$site_url" 524288 5 --write-out '%{url_effective}') || effective_url=""
  if effective_url=$(webapp_url "$effective_url"); then
    candidates=$(timeout 5s python3 "$(dirname "${BASH_SOURCE[0]}")/webapp-icon-links.py" "$directory/page.html" "$effective_url") || candidates=""
    while IFS= read -r candidate; do
      candidate=$(webapp_url "$candidate") || continue
      if webapp_download_icon "$directory" "$candidate"; then return 0; fi
    done <<< "$candidates"
  else
    effective_url=$site_url
  fi
  authority=${effective_url#*://}
  authority=${authority%%[/?#]*}
  origin="${effective_url%%://*}://$authority"
  WEBAPP_FETCH_DEADLINE=$((deadline - 5))
  if webapp_download_icon "$directory" "$origin/apple-touch-icon.png"; then return 0; fi
  WEBAPP_FETCH_DEADLINE=$deadline
  webapp_download_icon "$directory" 'https://www.google.com/s2/favicons' \
    --get --data-urlencode "domain=$site_url" --data-urlencode 'sz=256'
}
