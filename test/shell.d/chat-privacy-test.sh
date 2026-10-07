#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export MONARCH_PATH="$ROOT"

toggle="$ROOT/bin/monarch-toggle-chat-privacy"
user_config="$HOME/.config/niri/user.kdl"
legacy_config="$HOME/.local/state/monarch/chat-privacy.kdl"
rules="$ROOT/default/niri/chat-privacy.kdl"
flag="$HOME/.local/state/monarch/toggles/chat-privacy-off"
include="include \"$rules\" // monarch:chat-privacy"
mkdir -p "${user_config%/*}"
printf '// Personal settings\nlayout { gaps 9; }' >"$test_tmp/personal.kdl"
cp "$test_tmp/personal.kdl" "$user_config"

"$toggle" status | jq -e '.enabled == true' >/dev/null
"$toggle" init
[[ $(head -n 1 "$user_config") == "$include" ]]
tail -n +2 "$user_config" | cmp -s - "$test_tmp/personal.kdl"
[[ ! -e $legacy_config ]]
"$toggle" status | jq -e '.enabled == true' >/dev/null
pass "fresh installations enable chat masking"

"$toggle" off
[[ -f $flag ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" init
[[ -f $flag ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" status | jq -e '.enabled == false' >/dev/null
"$toggle" on
[[ ! -f $flag ]]
"$toggle" toggle
[[ -f $flag ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" toggle
[[ ! -f $flag && $(head -n 1 "$user_config") == "$include" ]]
pass "the toggle persists off across reconciliation and restores masking"

"$toggle" on
"$toggle" init
[[ $(grep -Fxc "$include" "$user_config") == 1 ]]
tail -n +2 "$user_config" | cmp -s - "$test_tmp/personal.kdl"
pass "repeated activation preserves personal settings without duplicate includes"

"$toggle" off
"$ROOT/bin/monarch-toggle" chat-privacy-off
mkdir -p "${legacy_config%/*}"
: >"$legacy_config"
"$toggle" init
[[ -f $flag && ! -e $legacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "existing disabled state migrates to the shared toggle flag"

"$ROOT/bin/monarch-toggle" chat-privacy-off
printf 'include "%s"\n' "$rules" >"$legacy_config"
"$toggle" init
[[ ! -f $flag && ! -e $legacy_config && $(head -n 1 "$user_config") == "$include" ]]
pass "reconciliation moves enabled legacy rules into user.kdl"

printf '// monarch-toggle chat-privacy-off\n' >"$legacy_config"
"$toggle" init
[[ -f $flag && ! -e $legacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "reconciliation migrates the previous generated off state"

mkdir -p "$test_tmp/incomplete-runtime/bin"
cp "$ROOT/bin/monarch-toggle" "$test_tmp/incomplete-runtime/bin/"
if MONARCH_PATH="$test_tmp/incomplete-runtime" "$toggle" on 2>/dev/null; then
  fail "chat masking enabled without its Niri rules"
fi
[[ -f $flag ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "a failed enable restores the shared toggle flag"

mv "$user_config" "$test_tmp/linked-user.kdl"
ln -s "$test_tmp/linked-user.kdl" "$user_config"
"$toggle" on
[[ -L $user_config && $(head -n 1 "$user_config") == "$include" ]]
if command -v niri >/dev/null 2>&1; then
  niri validate -c "$user_config" >/dev/null 2>&1
fi
"$toggle" off
[[ -L $user_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
if command -v niri >/dev/null 2>&1; then
  niri validate -c "$user_config" >/dev/null 2>&1
fi
pass "both configurations remain valid and preserve user.kdl symlinks"

"$ROOT/bin/monarch-menu" --tree | jq -e '
  .[] | select(.id == "setup.security.chat-privacy")
  | .action == "monarch-toggle-chat-privacy"
    and .checked == "! monarch-toggle-enabled chat-privacy-off"
' >/dev/null
pass "the Security menu exposes the chat masking state and action"
