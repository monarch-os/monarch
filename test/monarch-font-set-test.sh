#!/bin/bash

set -euo pipefail

case "${0##*/}" in
fc-list)
  printf 'fc-list\n' >>"$FONT_TEST_CASE/events"
  printf '%s\n' "$FONT_TEST_AVAILABLE"
  exit 0
  ;;
pkill)
  printf '%s\0' "$@" >>"$FONT_TEST_CASE/signals"
  exit 0
  ;;
pgrep) exit 1 ;;
notify-send) exit 97 ;;
monarch-hook)
  printf '%s\0' "$@" >"$FONT_TEST_CASE/hook"
  exit 0
  ;;
sed)
  if [[ -n ${FONT_TEST_SED_FAIL-} && ${*: -1} == *"$FONT_TEST_SED_FAIL" ]]; then
    exit 23
  fi
  exec "$FONT_TEST_SED" "$@"
  ;;
esac

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export FONT_TEST_SED=$(command -v sed)
mkdir -p "$TEST_TMP/bin"
for stub in fc-list pkill pgrep notify-send monarch-hook sed; do
  ln -s "$ROOT/test/monarch-font-set-test.sh" "$TEST_TMP/bin/$stub"
done
ln -s "$ROOT/bin/monarch-font-set" "$TEST_TMP/bin/monarch-font-set"
export PATH="$TEST_TMP/bin:$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

new_case() {
  FONT_TEST_CASE=$(mktemp -d "$TEST_TMP/case.XXXXXX")
  export FONT_TEST_CASE
  export HOME="$FONT_TEST_CASE/home"
  export FONT_TEST_AVAILABLE='Example Mono'
  export FONT_TEST_SED_FAIL=''
  mkdir -p "$HOME/.config"
  for config in alacritty kitty ghostty foot fontconfig; do
    cp -a "$ROOT/config/$config" "$HOME/.config/$config"
  done
  cp -a "$HOME/.config" "$FONT_TEST_CASE/before"
}

run_font() {
  if "$ROOT/bin/monarch-font-set" "$@" >"$FONT_TEST_CASE/output" 2>"$FONT_TEST_CASE/error"; then
    font_status=0
  else
    font_status=$?
  fi
}

assert_unchanged() {
  diff -r "$FONT_TEST_CASE/before" "$HOME/.config" || fail "rejected family changed configuration"
  [[ ! -e $FONT_TEST_CASE/hook && ! -e $FONT_TEST_CASE/signals ]] || fail "rejected family reloaded an app or called the hook"
}

assert_family() {
  local family="$1" foot_pattern
  python3 - "$family" <<'PY'
import os
import pathlib
import sys
import tomllib
import xml.etree.ElementTree as ET

family = sys.argv[1]
config = pathlib.Path(os.environ["HOME"]) / ".config"
with (config / "alacritty/alacritty.toml").open("rb") as file:
    alacritty = tomllib.load(file)
for key, style in (("normal", "Regular"), ("bold", "Bold"), ("italic", "Italic")):
    assert alacritty["font"][key] == {"family": family, "style": style}
kitty = (config / "kitty/kitty.conf").read_text().splitlines()
assert [line for line in kitty if line.startswith("font_family ")] == ["font_family " + family]
ghostty = (config / "ghostty/config").read_text().splitlines()
values = [line.split("=", 1)[1].strip() for line in ghostty if line.startswith("font-family = ")]
assert len(values) == 1 and values[0][0] == values[0][-1] == '"'
assert values[0][1:-1] == family
fonts = ET.parse(config / "fontconfig/fonts.conf")
matches = {match.findtext("test/string"): match.findtext("edit/string") for match in fonts.findall("match")}
assert matches["monospace"] == family
assert matches["sans-serif"] == "Liberation Sans"
hook = (pathlib.Path(os.environ["FONT_TEST_CASE"]) / "hook").read_bytes().split(b"\0")
assert hook == [b"font-set", family.encode(), b""]
PY
  foot_pattern=$(sed -n 's/^font=//p' "$HOME/.config/foot/foot.ini")
  [[ $(fc-pattern -f '%{family}' "$foot_pattern") == "$family" ]] || fail "Foot interpreted family characters as a font pattern"
  [[ $(fc-pattern -f '%{size}' "$foot_pattern") == "9" ]] || fail "Foot changed the font size"
}

for family in 'Example Mono' "Créateur's 日本語 Mono" 'IBM-Plex Mono-12' \
  'Mono & Serif/Variant | [Regular] "Quoted"' '-Mono' 'Mono.*' \
  'Mono/; touch "$FONT_TEST_CASE/injected"; #' \
  'Mono|e touch "$FONT_TEST_CASE/injected"|#' \
  '$(touch "$FONT_TEST_CASE/injected") `touch "$FONT_TEST_CASE/injected"`'; do
  new_case
  FONT_TEST_AVAILABLE="$family"
  run_font "$family"
  (( font_status == 0 )) || fail "font-set rejected a literal installed family: $family"
  assert_family "$family"
  [[ ! -e $FONT_TEST_CASE/injected ]] || fail "font-set executed a font name"
  run_font 'Absent Mono'
  (( font_status != 0 )) || fail "font-set accepted an absent family"
  FONT_TEST_AVAILABLE='Example Mono'
  run_font 'Example Mono'
  (( font_status == 0 )) || fail "font-set could not replace a previously escaped family"
  assert_family 'Example Mono'
done
pass "font-set writes literal families to TOML, Ghostty, Kitty, Foot and XML, preserving styles"

for family in '' ' ' ' Mono' 'Mono ' $'Mono\nNext' $'Mono\rNext' $'Mono\tNext' $'Mono\x1bNext' $'Mono\x7fNext' \
  'Mono:size=99' 'Mono,Other' 'Mono\Other'; do
  new_case
  FONT_TEST_AVAILABLE="$family"
  run_font "$family"
  (( font_status != 0 )) || fail "font-set accepted an incompatible family"
  assert_unchanged
  [[ ! -e $FONT_TEST_CASE/events ]] || fail "font-set searched for an invalid family"
done
pass "font-set rejects incompatible names before reads, writes, signals and hooks"

for family in '.*' '^Example' 'Example.*' 'Missing Mono'; do
  new_case
  run_font "$family"
  (( font_status != 0 )) || fail "font-set interpreted a family as a regular expression"
  assert_unchanged
done
new_case
FONT_TEST_AVAILABLE='eXaMpLe mOnO'
run_font 'Example Mono'
(( font_status == 0 )) || fail "font lookup became case-sensitive"
assert_family 'Example Mono'
pass "font lookup is literal and case-insensitive"

for count in 0 2; do
  new_case
  arguments=('Example Mono' extra)
  run_font "${arguments[@]:0:count}"
  (( font_status != 0 )) || fail "font-set accepted the wrong argument count"
  assert_unchanged
done
pass "font-set requires exactly one argument"

new_case
FONT_TEST_SED_FAIL='alacritty.toml'
run_font 'Example Mono'
(( font_status != 0 )) || fail "font-set ignored a configuration write failure"
assert_unchanged
pass "font-set stops on a configuration write failure"

for command in "$ROOT/bin/monarch-font-set" "$TEST_TMP/bin/monarch-font-set"; do
  new_case
  env -u MONARCH_PATH "$command" 'Example Mono' >"$FONT_TEST_CASE/output" 2>"$FONT_TEST_CASE/error" ||
    fail "font-set could not resolve its helper without MONARCH_PATH"
  assert_family 'Example Mono'
done
pass "font-set resolves its helper through checkout and symlink paths"
