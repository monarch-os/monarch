#!/bin/bash

set -euo pipefail

case "${0##*/}" in
monarch-launch-floating-terminal-with-presentation)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/terminal"
  exit 0
  ;;
monarch-pkg-add)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/packages"
  printf 'install\n' >>"$INSTALL_TEST_CASE/events"
  exit "${INSTALL_TEST_PKG_STATUS:-0}"
  ;;
setsid)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/setsid"
  exec "$@"
  ;;
uwsm-app)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/uwsm"
  [[ $1 == "--" ]]
  shift
  exec "$@"
  ;;
gtk-launch)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/desktop"
  printf 'launch\n' >>"$INSTALL_TEST_CASE/events"
  exit 0
  ;;
sleep)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/sleep"
  printf 'sleep\n' >>"$INSTALL_TEST_CASE/events"
  exit "${INSTALL_TEST_SLEEP_STATUS:-0}"
  ;;
monarch-font-set)
  printf '%s\0' "$@" >"$INSTALL_TEST_CASE/font"
  printf 'font\n' >>"$INSTALL_TEST_CASE/events"
  exit "${INSTALL_TEST_FONT_STATUS:-0}"
  ;;
package-two | package-three)
  exit 97
  ;;
esac

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin" "$TEST_TMP/home"
for stub in monarch-launch-floating-terminal-with-presentation monarch-pkg-add setsid uwsm-app gtk-launch sleep monarch-font-set package-two package-three; do
  ln -s "$ROOT/test/monarch-install-helpers-test.sh" "$TEST_TMP/bin/$stub"
done
export PATH="$TEST_TMP/bin:$ROOT/bin:$PATH"
export HOME="$TEST_TMP/home"
export MONARCH_PATH="$ROOT"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_args() {
  local file="$1"
  shift
  local -a actual=()
  [[ -f $INSTALL_TEST_CASE/$file ]] || fail "$file was not called"
  mapfile -d '' -t actual <"$INSTALL_TEST_CASE/$file"
  [[ ${#actual[@]} == $# ]] || fail "$file received the wrong argument count"
  local argument index=0
  for argument in "$@"; do
    [[ ${actual[index]} == "$argument" ]] || fail "$file changed argument $index"
    index=$((index + 1))
  done
}

new_case() {
  INSTALL_TEST_CASE=$(mktemp -d "$TEST_TMP/case.XXXXXX")
  export INSTALL_TEST_CASE
  export INSTALL_TEST_PKG_STATUS=0
  export INSTALL_TEST_SLEEP_STATUS=0
  export INSTALL_TEST_FONT_STATUS=0
}

run_helper() {
  local helper="$1"
  shift
  if bash -e "$ROOT/bin/$helper" "$@" >"$INSTALL_TEST_CASE/helper-output" 2>"$INSTALL_TEST_CASE/helper-error"; then
    helper_status=0
  else
    helper_status=$?
  fi
}

run_terminal() {
  local -a terminal_args=()
  [[ -f $INSTALL_TEST_CASE/terminal ]] || fail "floating terminal was not called"
  mapfile -d '' -t terminal_args <"$INSTALL_TEST_CASE/terminal"
  (( ${#terminal_args[@]} == 1 )) || fail "floating terminal needs one shell command"
  # Detached launchers inherit FD 3, so this pipe closes only after their stubs finish.
  if terminal_output=$(bash -c "${terminal_args[0]}" 3>&1); then
    terminal_status=0
  else
    terminal_status=$?
  fi
}

assert_no_launch() {
  [[ ! -e $INSTALL_TEST_CASE/setsid && ! -e $INSTALL_TEST_CASE/desktop && ! -e $INSTALL_TEST_CASE/font ]] ||
    fail "failed installation still launched or selected an app"
}

for helper in monarch-install-app monarch-install-and-launch; do
  new_case
  run_helper "$helper" 'Creator Apps' 'obs-studio pinta kdenlive' org.example.Creator
  (( helper_status == 0 )) || fail "$helper rejected multiple packages under errexit"
  run_terminal
  (( terminal_status == 0 )) || fail "$helper installation failed"
  [[ $terminal_output == "Installing Creator Apps..." ]] || fail "$helper changed the display message"
  assert_args packages obs-studio pinta kdenlive
  if [[ $helper == "monarch-install-and-launch" ]]; then
    assert_args setsid uwsm-app -- gtk-launch org.example.Creator
    assert_args uwsm -- gtk-launch org.example.Creator
    assert_args desktop org.example.Creator
    [[ $(<"$INSTALL_TEST_CASE/events") == $'install\nlaunch' ]] || fail "app launched before installation finished"
  else
    assert_no_launch
  fi
  pass "$helper preserves multiple packages, display name and launch order"

  for name in $'Example\x27; touch "$INSTALL_TEST_CASE/name-injected"; #' \
    $'Creator\x27s $(touch "$INSTALL_TEST_CASE/name-injected") `touch "$INSTALL_TEST_CASE/name-injected"` \\font\nNext'; do
    new_case
    desktop_id=$'org.example.App\x27"; $(touch "$INSTALL_TEST_CASE/desktop-injected") `touch "$INSTALL_TEST_CASE/desktop-injected"`\nNext'
    run_helper "$helper" "$name" vim "$desktop_id"
    (( helper_status == 0 )) || fail "$helper rejected a literal display name"
    run_terminal
    [[ ! -e $INSTALL_TEST_CASE/name-injected && ! -e $INSTALL_TEST_CASE/desktop-injected ]] || fail "$helper executed an argument as shell code"
    (( terminal_status == 0 )) || fail "$helper could not display a literal name"
    [[ $terminal_output == "Installing ${name}..." ]] || fail "$helper interpreted display-name characters"
    assert_args packages vim
    if [[ $helper == "monarch-install-and-launch" ]]; then
      assert_args desktop "$desktop_id"
    fi
  done
  pass "$helper treats quotes, substitutions, backticks and newlines in labels as data"

  new_case
  run_helper "$helper" Example $' \tpackage-one\n package-two\t package-three \n' org.example.App
  (( helper_status == 0 )) || fail "$helper rejected multiline packages under errexit"
  run_terminal
  (( terminal_status == 0 )) || fail "$helper interpreted multiline packages as commands"
  assert_args packages package-one package-two package-three
  pass "$helper splits spaces, tabs and newlines into package arguments"

  for packages in '' $' \t\n ' '-Syu' 'vim --root /tmp' 'vim --noconfirm' \
    'vim; touch "$INSTALL_TEST_CASE/package-injected"' \
    '$(touch "$INSTALL_TEST_CASE/package-injected")' \
    '`touch "$INSTALL_TEST_CASE/package-injected"`' \
    '*' 'vim?' '[a-z]' 'vim{,-git}' 'extra/vim' '.hidden' 'vim|id' \
    'vim>file' 'vim&' 'vim\\name' $'vim\r' $'vim\ntouch "$INSTALL_TEST_CASE/package-injected"'; do
    new_case
    run_helper "$helper" Example "$packages" org.example.App
    (( helper_status != 0 )) || fail "$helper accepted invalid package input: $packages"
    [[ ! -e $INSTALL_TEST_CASE/terminal ]] || fail "$helper opened a terminal for invalid packages"
    [[ ! -e $INSTALL_TEST_CASE/package-injected ]] || fail "$helper evaluated invalid packages"
  done
  pass "$helper rejects shell syntax, globs, option-like names and empty package lists before opening a terminal"

  new_case
  run_helper "$helper" Example 'a Package_1 pkg.name libstdc++ app@next +pkg _pkg' org.example.App
  (( helper_status == 0 )) || fail "$helper rejected valid package-name characters"
  run_terminal
  assert_args packages a Package_1 pkg.name libstdc++ app@next +pkg _pkg
  pass "$helper accepts the package-name alphabet"

  new_case
  INSTALL_TEST_PKG_STATUS=23
  run_helper "$helper" Example vim org.example.App
  (( helper_status == 0 )) || fail "$helper did not open its installer"
  run_terminal
  (( terminal_status == 23 )) || fail "$helper lost the installation failure status"
  assert_no_launch
  pass "$helper stops after a failed installation"

  new_case
  run_helper "$helper"
  (( helper_status != 0 )) || fail "$helper accepted missing arguments"
  [[ ! -e $INSTALL_TEST_CASE/terminal ]] || fail "$helper opened a terminal with missing arguments"
done

for helper in monarch-install-app monarch-install-and-launch monarch-install-font; do
  ln -s "$ROOT/bin/$helper" "$TEST_TMP/bin/$helper"
  for command in "$ROOT/bin/$helper" "$TEST_TMP/bin/$helper"; do
    new_case
    if env -u MONARCH_PATH bash -e "$command" Example vim org.example.App; then
      run_terminal
      assert_args packages vim
    else
      fail "$command cannot locate the shared helper without MONARCH_PATH"
    fi
  done
done
pass "checkout and symlink invocations locate the shared helper without MONARCH_PATH"

for family in 'CaskaydiaMono Nerd Font' "Créateur's Mono" 'Mono-12 & Serif/Variant | [Regular] "Quoted"' \
  '$(touch "$INSTALL_TEST_CASE/font-injected") `touch "$INSTALL_TEST_CASE/font-injected"`'; do
  new_case
  name=$'Creator\x27s $(touch "$INSTALL_TEST_CASE/name-injected")\nFont'
  run_helper monarch-install-font "$name" ttf-example "$family"
  (( helper_status == 0 )) || fail "font installer rejected a literal family"
  run_terminal
  (( terminal_status == 0 )) || fail "font installer failed to select a literal family"
  [[ $terminal_output == "Installing ${name}..." ]] || fail "font installer changed the display name"
  assert_args packages ttf-example
  assert_args sleep 2
  assert_args font "$family"
  [[ $(<"$INSTALL_TEST_CASE/events") == $'install\nsleep\nfont' ]] || fail "font installer ran commands out of order"
  [[ ! -e $INSTALL_TEST_CASE/font-injected && ! -e $INSTALL_TEST_CASE/name-injected ]] || fail "font installer evaluated its arguments"
done
pass "font installer preserves literal names and selects the family after installation"

for package in '' 'ttf-one ttf-two' $'ttf-one\nttf-two' $'ttf-one\tttf-two' ' ttf-one' '-Syu' \
  'ttf-one;id' 'ttf-*' 'extra/ttf-one' '$(touch "$INSTALL_TEST_CASE/package-injected")'; do
  new_case
  run_helper monarch-install-font Example "$package" 'Example Mono'
  (( helper_status != 0 )) || fail "font installer accepted an invalid or multiple package name"
  [[ ! -e $INSTALL_TEST_CASE/terminal ]] || fail "font installer opened a terminal for invalid packages"
done
pass "font installer accepts exactly one valid package name"

for family in '' ' ' ' Mono' 'Mono ' $'Mono\nNext' $'Mono\rNext' $'Mono\tNext' $'Mono\x1bNext' $'Mono\x7fNext' \
  'Mono:size=99' 'Mono,Other' 'Mono\Other'; do
  new_case
  run_helper monarch-install-font Example ttf-example "$family"
  (( helper_status != 0 )) || fail "font installer accepted an incompatible family"
  [[ ! -e $INSTALL_TEST_CASE/terminal && ! -e $INSTALL_TEST_CASE/packages ]] || fail "font validation ran after installation started"
done
pass "font installer rejects control characters and font patterns before installation"

for count in 0 1 2 4; do
  new_case
  arguments=(Example ttf-example 'Example Mono' extra)
  run_helper monarch-install-font "${arguments[@]:0:count}"
  (( helper_status != 0 )) || fail "font installer accepted the wrong argument count"
  [[ ! -e $INSTALL_TEST_CASE/terminal ]] || fail "font installer opened a terminal with the wrong argument count"
done
pass "font installer requires exactly three arguments"

for stage in PKG SLEEP FONT; do
  new_case
  export "INSTALL_TEST_${stage}_STATUS=23"
  run_helper monarch-install-font Example ttf-example 'Example Mono'
  (( helper_status == 0 )) || fail "font installer did not open its terminal"
  run_terminal
  (( terminal_status == 23 )) || fail "font installer lost the $stage failure status"
  case "$stage" in
  PKG)
    assert_no_launch
    [[ ! -e $INSTALL_TEST_CASE/sleep ]] || fail "font installer continued after installation failed"
    ;;
  SLEEP) assert_no_launch ;;
  FONT) assert_args font 'Example Mono' ;;
  esac
done
pass "font installer stops at the failed stage and preserves its exit status"

menu_tree=$(env HOME="$TEST_TMP/home" "$ROOT/bin/monarch-menu" --tree)
font_count=$(jq '[.[] | select(.id | startswith("install.font."))] | length' <<<"$menu_tree")
[[ $font_count == "6" ]] || fail "expected six font installation actions"
while IFS='|' read -r id package font message; do
  action=$(jq -er --arg id "install.font.$id" '.[] | select(.id == $id) | .action' <<<"$menu_tree")
  [[ $action == monarch-install-font\ * ]] || fail "$id does not use the font installer"
  disabled=$(jq -er --arg id "install.font.$id" '.[] | select(.id == $id) | .disabled' <<<"$menu_tree")
  [[ $disabled == "monarch-pkg-present $package" ]] || fail "$id changed its installed guard"
  for status in 0 23; do
    new_case
    INSTALL_TEST_PKG_STATUS=$status
    bash -e -c "$action"
    run_terminal
    assert_args packages "$package"
    [[ $terminal_output == "Installing ${message}..." ]] || fail "$id changed its install message"
    if (( status == 0 )); then
      (( terminal_status == 0 )) || fail "$id could not install its font"
      assert_args sleep 2
      assert_args font "$font"
      [[ $(<"$INSTALL_TEST_CASE/events") == $'install\nsleep\nfont' ]] || fail "$id selects its font before installation"
    else
      (( terminal_status == status )) || fail "$id lost the installation failure status"
      assert_no_launch
      [[ ! -e $INSTALL_TEST_CASE/sleep ]] || fail "$id continued after a failed installation"
    fi
  done
  pass "menu font $id installs its package and selects its font only after success"
done <<'FONTS'
cascadia|ttf-cascadia-mono-nerd|CaskaydiaMono Nerd Font|Cascadia Mono
meslo|ttf-meslo-nerd|MesloLGL Nerd Font|Meslo LG Mono
fira|ttf-firacode-nerd|FiraCode Nerd Font|Fira Code
victor|ttf-victor-mono-nerd|VictorMono Nerd Font|Victor Code
bitstream|ttf-bitstream-vera-mono-nerd|BitstromWera Nerd Font|Bitstream Vera Code
iosevka|ttf-iosevka-nerd|Iosevka Nerd Font Mono|Iosevka
FONTS
