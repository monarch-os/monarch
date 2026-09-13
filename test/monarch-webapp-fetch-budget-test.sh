#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
source "$ROOT/install/helpers/webapps.sh"

base64 -d > "$TEST_TMP/image.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF
PAGE_URL='https://example.com/redirected/page.html'
GOOGLE_URL='https://www.google.com/s2/favicons'
APPLE_URL='https://example.com/apple-touch-icon.png'

fail() {
  printf 'not ok - %s\n' "$1" >&2
  [[ ! -f $CASE_DIR/events ]] || cat "$CASE_DIR/events" >&2
  exit 1
}

curl() {
  local url=${!#} destination='' duration=0
  while (( $# )); do
    case $1 in
      --output) destination=$2; shift ;;
      --max-time) duration=$2; shift ;;
    esac
    shift
  done
  (( duration > 0 && duration <= 15 )) || fail 'download has no bounded timeout'
  printf 'download %s %s\n' "$url" "$duration" >> "$CASE_DIR/events"
  if [[ $destination == */page.html ]]; then
    printf '<link rel="icon" href="one.png"><link rel="icon" href="two.png"><link rel="icon" href="three.png">\n' > "$destination"
    printf '%s' "$PAGE_URL"
    return 0
  fi
  LAST_ICON_URL=$url
  if [[ ( $url == "$GOOGLE_URL" && $MODE != "all-fail" ) || $MODE == "decodes" ||
    $MODE == "site-success" || ( $MODE == "apple-success" && $url == "$APPLE_URL" ) ]]; then
    cp "$TEST_TMP/image.png" "$destination"
    return 0
  fi
  SECONDS=$((SECONDS + duration))
  return 28
}

monarch-cmd-present() {
  [[ $1 == "magick" ]]
}

timeout() {
  local duration=${1%s} destination=${!#}
  shift
  case $1 in
    python3) "$@" ;;
    prlimit)
      (( duration > 0 && duration <= 10 )) || fail 'decoder has no bounded timeout'
      printf 'decode %s %s\n' "$LAST_ICON_URL" "$duration" >> "$CASE_DIR/events"
      if [[ $MODE == "decodes" && $LAST_ICON_URL != "$GOOGLE_URL" ]]; then
        SECONDS=$((SECONDS + duration))
        return 124
      fi
      cp "$TEST_TMP/image.png" "${destination#PNG:}"
      ;;
    *) fail 'unexpected timed command' ;;
  esac
}

# Unsetting Bash's special variable makes the simulated clock independent of wall time.
unset SECONDS
new_case() {
  CASE_DIR=$(mktemp -d "$TEST_TMP/case.XXXXXX")
  MODE=$1
  SECONDS=0
}

new_case downloads
if ! webapp_fetch_site_icon "$CASE_DIR" "$PAGE_URL"; then
  fail 'slow site icons prevented the Google fallback'
fi
[[ -s $CASE_DIR/icon.png ]] || fail 'Google fallback did not produce an icon'
grep -Fqx "download $APPLE_URL 5" "$CASE_DIR/events" || fail 'Apple did not retain five seconds'
grep -Fqx "download $GOOGLE_URL 5" "$CASE_DIR/events" || fail 'Google did not retain five seconds'
grep -Fqx "decode $GOOGLE_URL 5" "$CASE_DIR/events" || fail 'Google decoding exceeded its remaining budget'
(( SECONDS <= 30 )) || fail 'icon discovery exceeded thirty seconds'
printf 'ok - slow site downloads preserve the Apple and Google fallback budgets\n'

new_case decodes
webapp_fetch_site_icon "$CASE_DIR" "$PAGE_URL" || fail 'slow image decoding prevented the Google fallback'
[[ -s $CASE_DIR/icon.png ]] || fail 'Google fallback did not produce an icon after decoder timeouts'
grep -Fqx "download $APPLE_URL 5" "$CASE_DIR/events" || fail 'site decoding consumed the Apple reserve'
grep -Fqx "decode $APPLE_URL 5" "$CASE_DIR/events" || fail 'Apple decoding exceeded its remaining budget'
grep -Fqx "download $GOOGLE_URL 5" "$CASE_DIR/events" || fail 'Apple decoding consumed the Google reserve'
grep -Fqx "decode $GOOGLE_URL 5" "$CASE_DIR/events" || fail 'Google decoding exceeded the total budget'
(( SECONDS <= 30 )) || fail 'slow decoding exceeded thirty seconds'
printf 'ok - slow decoders preserve the fallback budgets for downloads and decoding\n'

new_case all-fail
if webapp_fetch_site_icon "$CASE_DIR" "$PAGE_URL"; then
  fail 'discovery succeeded despite all requests timing out'
fi
[[ $(< "$CASE_DIR/events") == "download $PAGE_URL 5
download https://example.com/redirected/one.png 15
download https://example.com/redirected/two.png 5
download $APPLE_URL 5
download $GOOGLE_URL 5" ]] || fail 'timed-out discovery skipped or reordered its fallbacks'
(( SECONDS == 30 )) || fail 'all failed requests did not stop at the thirty-second limit'
[[ ! -e $CASE_DIR/icon.png ]] || fail 'failed discovery left a completed icon'
printf 'ok - all slow failures try both fallbacks and stop at thirty seconds\n'

new_case site-success
webapp_fetch_site_icon "$CASE_DIR" "$PAGE_URL" || fail 'a valid site icon was not accepted'
[[ -s $CASE_DIR/icon.png ]] || fail 'successful discovery did not produce an icon'
if grep -Eq 'two\.png|three\.png|apple-touch-icon|google\.com' "$CASE_DIR/events"; then
  fail 'discovery continued after a valid site icon'
fi
printf 'ok - a valid site icon returns before later candidates and fallbacks\n'

new_case apple-success
webapp_fetch_site_icon "$CASE_DIR" "$PAGE_URL" || fail 'a valid Apple fallback was not accepted'
[[ -s $CASE_DIR/icon.png ]] || fail 'successful Apple fallback did not produce an icon'
grep -Fqx "decode $APPLE_URL 5" "$CASE_DIR/events" || fail 'Apple decoder did not keep the Google reserve'
if grep -Fq "$GOOGLE_URL" "$CASE_DIR/events"; then
  fail 'Google was requested after a valid Apple icon'
fi
printf 'ok - a valid Apple fallback returns before Google\n'
