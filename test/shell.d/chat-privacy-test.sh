#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export MONARCH_PATH="$ROOT"

toggle="$ROOT/bin/monarch-toggle-chat-privacy"
reconcile="$ROOT/install/reconcile/chat-privacy.sh"
user_config="$HOME/.config/niri/user.kdl"
privacy_config="$HOME/.config/niri/chat-privacy.kdl"
legacy_config="$HOME/.local/state/monarch/chat-privacy.kdl"
rules="$ROOT/default/niri/chat-privacy.kdl"
flag="$HOME/.local/state/monarch/toggles/chat-privacy-off"
mkdir -p "${user_config%/*}"
printf '// Personal settings\nlayout { gaps 9; }' >"$test_tmp/personal.kdl"
cp "$test_tmp/personal.kdl" "$user_config"

"$toggle" status | jq -e '.enabled == true' >/dev/null
"$toggle" init
cmp -s "$privacy_config" "$rules"
cmp -s "$user_config" "$test_tmp/personal.kdl"
[[ ! -e $legacy_config ]]
"$toggle" status | jq -e '.enabled == true' >/dev/null
pass "fresh installations enable chat masking"

"$toggle" off
[[ -f $flag && -f $privacy_config && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" init
[[ -f $flag && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" status | jq -e '.enabled == false' >/dev/null
"$toggle" on
[[ ! -f $flag ]]
"$toggle" toggle
[[ -f $flag && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
"$toggle" toggle
[[ ! -f $flag ]]
cmp -s "$privacy_config" "$rules"
pass "the toggle persists off across reconciliation and restores masking"

"$toggle" on
privacy_inode=$(stat -c %i "$privacy_config")
"$toggle" init
[[ $(stat -c %i "$privacy_config") == "$privacy_inode" ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "repeated activation avoids rewriting the config and leaves user.kdl untouched"

"$toggle" off
"$ROOT/bin/monarch-toggle" chat-privacy-off
mkdir -p "${legacy_config%/*}"
: >"$legacy_config"
"$toggle" init
[[ ! -f $flag && -f $legacy_config ]]
bash "$reconcile"
[[ -f $flag && ! -e $legacy_config && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "existing disabled state migrates to the shared toggle flag"

"$ROOT/bin/monarch-toggle" chat-privacy-off
printf 'include "%s"\n' "$rules" >"$legacy_config"
bash "$reconcile"
[[ ! -f $flag && ! -e $legacy_config ]]
cmp -s "$privacy_config" "$rules"
pass "reconciliation moves enabled legacy rules into the Niri config directory"

"$toggle" off
printf 'include "%s"\n' "$rules" >"$legacy_config"
bash "$reconcile"
[[ -f $flag && ! -e $legacy_config && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
bash "$reconcile"
[[ -f $flag && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "reconciliation preserves the shared preference and tolerates repeat runs"

mkdir -p "$test_tmp/incomplete-runtime/bin"
cp "$ROOT/bin/monarch-toggle" "$test_tmp/incomplete-runtime/bin/"
cp "$toggle" "$test_tmp/incomplete-runtime/bin/"
if MONARCH_PATH="$test_tmp/incomplete-runtime" "$toggle" on 2>/dev/null; then
  fail "chat masking enabled without its Niri rules"
fi
[[ -f $flag && ! -s $privacy_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
pass "a failed enable restores the shared toggle flag"

"$toggle" on
printf 'include "%s"\n' "$rules" >"$legacy_config"
cp "$privacy_config" "$test_tmp/before-failure.kdl"
if MONARCH_PATH="$test_tmp/incomplete-runtime" bash "$reconcile" 2>/dev/null; then
  fail "reconciliation succeeded without its Niri rules"
fi
[[ -f $legacy_config && ! -f $flag ]]
cmp -s "$privacy_config" "$test_tmp/before-failure.kdl"
bash "$reconcile"
[[ ! -e $legacy_config ]]
pass "failed reconciliation preserves the legacy configuration for retry"

mv "$user_config" "$test_tmp/linked-user.kdl"
ln -s "$test_tmp/linked-user.kdl" "$user_config"
"$toggle" on
[[ -L $user_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
printf 'include "%s/default/niri/windows.kdl"\n' "$ROOT" >"$test_tmp/windows.kdl"
if command -v niri >/dev/null 2>&1; then
  niri validate -c "$test_tmp/windows.kdl" >/dev/null 2>&1
  printf 'window-rule {\n' >"$privacy_config"
  if niri validate -c "$test_tmp/windows.kdl" >/dev/null 2>&1; then
    fail "windows.kdl does not load the chat privacy config"
  fi
  "$toggle" init
fi
"$toggle" off
[[ -L $user_config ]]
cmp -s "$user_config" "$test_tmp/personal.kdl"
if command -v niri >/dev/null 2>&1; then
  niri validate -c "$test_tmp/windows.kdl" >/dev/null 2>&1
fi
pass "windows.kdl loads both privacy states and user.kdl remains untouched"

"$ROOT/bin/monarch-menu" --tree | jq -e '
  .[] | select(.id == "setup.security.chat-privacy")
  | .action == "monarch-toggle-chat-privacy"
    and .checked == "! monarch-toggle-enabled chat-privacy-off"
' >/dev/null
pass "the Security menu exposes the chat masking state and action"
