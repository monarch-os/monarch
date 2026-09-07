#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
PARSER="$ROOT/install/helpers/webapp-icon-links.py"
PAGE_URL='https://example.com/redirected/page.html'

check_links() {
  local label=$1 expected=$2 html=$3 actual
  printf '%s' "$html" > "$TMP/page.html"
  actual=$(python3 "$PARSER" "$TMP/page.html" "${4:-$PAGE_URL}")
  if [[ $actual != "$expected" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$label"
}

check_rejected() {
  local label=$1
  shift
  if python3 "$PARSER" "$@" > "$TMP/stdout" 2> "$TMP/stderr"; then
    printf 'FAIL: accepted %s\n' "$label" >&2
    exit 1
  fi
  [[ ! -s $TMP/stdout && -s $TMP/stderr ]]
  printf 'PASS: rejects %s without candidate output\n' "$label"
}

check_links 'case, attribute order, rel tokens and apple priority' \
  $'https://example.com/large.png\nhttps://example.com/small.png\nhttps://example.com/favicon.png' \
  '<LINK HREF="/favicon.png" SIZES="1024x1024" REL="shortcut ICON">
   <link sizes="120x120" rel="apple-touch-icon" href="/small.png">
   <LiNk href="/large.png" data-label="literal > text" sizes="180X180" ReL="alternate APPLE-TOUCH-ICON-PRECOMPOSED">'

check_links 'largest declared size wins within one category' \
  $'https://example.com/512.png\nhttps://example.com/96.png\nhttps://example.com/32.png' \
  '<link rel="icon" sizes="32x32" href="/32.png">
   <link rel="icon" sizes="16x16 512x512" href="/512.png">
   <link rel="icon" sizes="96x96 invalid 0x1000" href="/96.png">
   <link rel="icon" sizes="any" href="/unknown.png">'

check_links 'first valid base applies even to earlier links' \
  $'https://example.com/assets/icon.png\nhttps://example.com/assets/other.png' \
  '<link href="icon.png" rel="icon">
   <base href="javascript:alert(1)"><base href="https:///missing">
   <base href="../assets/"><base href="https://ignored.example/">
   <link rel="icon" href="other.png">'

check_links 'absolute base and scheme-relative icon resolution' \
  $'http://images.example:8080/icons/one.png\nhttp://cdn.example/two.png' \
  '<base href="http://images.example:8080/icons/"><link rel="icon" href="one.png">
   <link rel="icon" href="//cdn.example/two.png">'

check_links 'effective URL, entities and literal URL data survive' \
  $'https://example.com/redirected/icon%20file.png?v=1&next=%2Fpath#icon\nhttps://example.com/redirected/$(id)-`id`.png?x=$HOME' \
  '<link rel="icon" href="icon%20file.png?v=1&amp;next=%2Fpath#icon">
   <link rel="icon" href="$(id)-`id`.png?x=$HOME">'

check_links 'comments and scripts cannot supply links or base URLs' \
  'https://example.com/redirected/actual.png' \
  '<!-- <base href="https://comment.example/"><link rel="apple-touch-icon" href="/comment.png"> -->
   <SCRIPT>const text = "<base href=\"https://script.example/\"><link rel=\"apple-touch-icon\" href=\"/script.png\">";</SCRIPT>
   <link rel="icon" href="actual.png">'

check_links 'invalid schemes and authorities do not consume the limit' \
  $'https://example.com/one.png\nhttps://example.com/two.png\nhttps://example.com/three.png' \
  '<link rel="apple-touch-icon" href="file:///tmp/icon.png">
   <link rel="apple-touch-icon" href="data:image/png;base64,AAAA">
   <link rel="apple-touch-icon" href="javascript:alert(1)">
   <link rel="apple-touch-icon" href="http:relative.png">
   <link rel="apple-touch-icon" href="https:///missing.png">
   <link rel="apple-touch-icon" href="//">
   <link rel="apple-touch-icon" href="///missing.png">
   <link rel="apple-touch-icon" href="https://:443/icon.png">
   <link rel="apple-touch-icon" href="https://example.com:65536/icon.png">
   <link rel="apple-touch-icon" href="https://example.com:abc/icon.png">
   <link rel="apple-touch-icon" href="https://example.com:/icon.png">
   <link rel="apple-touch-icon" href="https://[broken]/icon.png">
   <link rel="apple-touch-icon" href="https://[::1]junk/icon.png">
   <link rel="apple-touch-icon" href="https://example.com\evil/icon.png">
   <link rel="icon" href="/one.png"><link rel="icon" href="/two.png">
   <link rel="icon" href="/three.png"><link rel="icon" href="/four.png">'

check_links 'interior whitespace and controls are rejected after entity decoding' \
  'https://example.com/valid.png' \
  $'<link rel="icon" href="/bad name.png"><link rel="icon" href="/bad\tname.png">
    <link rel="icon" href="/bad\nname.png"><link rel="icon" href="/bad\x7fname.png">
    <link rel="icon" href="/bad&#10;name.png"><link rel="icon" href="/bad&nbsp;name.png">
    <link rel="icon" href="/bad\xc2\x80name.png">
    <link rel="icon" href="/bad\x01name.png"><link rel="icon" href=" /valid.png ">'

check_links 'HTML whitespace is trimmed only around URL attributes' \
  'https://example.com/assets/icon.png' \
  $'<base href=" \t../assets/\n"><link rel="icon" href="\n icon.png \t">'

check_links 'duplicate resolved URLs do not consume the three-URL limit' \
  $'https://example.com/redirected/shared.png\nhttps://example.com/two.png\nhttps://example.com/three.png' \
  '<link rel="apple-touch-icon" sizes="180x180" href="shared.png">
   <link rel="icon" href="https://example.com/redirected/shared.png">
   <link rel="icon" href="./shared.png"><link rel="icon" href="/two.png">
   <link rel="icon" href="/three.png"><link rel="icon" href="/four.png">'

check_links 'rel matching requires exact icon tokens and nonempty href' '' \
  '<link rel="apple-touch-icon-extra" href="/wrong.png">
   <link rel="mask-icon" href="/mask.svg"><link rel="shortcut" href="/shortcut.png">
   <link href="/missing-rel.png"><link rel="icon"><link rel="icon" href="">
   <link rel="icon" href="   ">'

check_links 'duplicate attributes follow HTML first-attribute semantics' \
  'https://example.com/first.png' \
  '<link rel="icon" href="/first.png" href="/second.png">
   <link rel="none" rel="icon" href="/ignored.png">'

check_links 'invalid UTF-8 uses replacement without dropping valid links' \
  'https://example.com/valid.png' $'\xff<link rel="icon" href="/valid.png">'

check_links 'IPv6 and HTTP URLs remain valid' \
  $'https://[::1]:8443/icon.png\nhttp://example.com:80/icon.png' \
  '<link rel="icon" href="https://[::1]:8443/icon.png"><link rel="icon" href="http://example.com:80/icon.png">'

check_links 'oversized and malformed dimension declarations are ignored' \
  $'https://example.com/valid.png\nhttps://example.com/unknown.png' \
  '<link rel="icon" sizes="99999999999999999999x99999999999999999999 999x -1x100" href="/unknown.png">
   <link rel="icon" sizes="32x32" href="/valid.png">'

printf '%s' '<link rel="icon" href="/bounded.png">' > "$TMP/page.html"
truncate -s 524288 "$TMP/page.html"
[[ $(python3 "$PARSER" "$TMP/page.html" "$PAGE_URL") == 'https://example.com/bounded.png' ]]
printf 'PASS: accepts a page at the 512 KiB limit\n'
truncate -s 524289 "$TMP/page.html"
check_rejected 'a page over 512 KiB' "$TMP/page.html" "$PAGE_URL"
check_rejected 'missing CLI arguments'
check_rejected 'extra CLI arguments' "$TMP/page.html" "$PAGE_URL" extra
check_rejected 'missing page files' "$TMP/missing.html" "$PAGE_URL"
check_rejected 'nonregular page files' "$TMP" "$PAGE_URL"
check_rejected 'non-HTTP effective URLs' "$TMP/page.html" 'file:///tmp/page.html'
check_rejected 'invalid effective URL ports' "$TMP/page.html" 'https://example.com:99999/page'
check_rejected 'raw whitespace in effective URLs' "$TMP/page.html" ' https://example.com/page'
