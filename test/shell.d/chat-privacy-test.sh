#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export MONARCH_PATH="$ROOT"

toggle="$ROOT/bin/monarch-toggle-chat-privacy"
state="$HOME/.local/state/monarch/chat-privacy.kdl"
rules="$ROOT/default/niri/chat-privacy.kdl"
flag="$HOME/.local/state/monarch/toggles/chat-privacy-off"

"$toggle" status | jq -e '.enabled == true' >/dev/null
"$toggle" init
[[ $(<"$state") == "include \"$rules\"" ]]
"$toggle" status | jq -e '.enabled == true' >/dev/null
pass "fresh installations enable chat masking"

"$toggle" off
[[ -f $flag && $(<"$state") == "// monarch-toggle chat-privacy-off" ]]
"$toggle" init
[[ -f $flag && $(<"$state") == "// monarch-toggle chat-privacy-off" ]]
"$toggle" status | jq -e '.enabled == false' >/dev/null
"$toggle" on
[[ ! -f $flag ]]
"$toggle" toggle
[[ -f $flag && $(<"$state") == "// monarch-toggle chat-privacy-off" ]]
"$toggle" toggle
[[ ! -f $flag && $(<"$state") == "include \"$rules\"" ]]
pass "the toggle persists off across reconciliation and restores masking"

"$toggle" off
"$ROOT/bin/monarch-toggle" chat-privacy-off
: >"$state"
[[ ! -f $flag && ! -s $state ]]
"$toggle" init
[[ -f $flag && $(<"$state") == "// monarch-toggle chat-privacy-off" ]]
pass "existing disabled state migrates to the shared toggle flag"

"$ROOT/bin/monarch-toggle" chat-privacy-off
"$toggle" init
[[ ! -f $flag && $(<"$state") == "include \"$rules\"" ]]
pass "reconciliation derives the KDL include from the shared flag"

"$toggle" off
mkdir -p "$test_tmp/incomplete-runtime/bin"
cp "$ROOT/bin/monarch-toggle" "$test_tmp/incomplete-runtime/bin/"
if MONARCH_PATH="$test_tmp/incomplete-runtime" "$toggle" on 2>/dev/null; then
  fail "chat masking enabled without its Niri rules"
fi
[[ -f $flag && $(<"$state") == "// monarch-toggle chat-privacy-off" ]]
pass "a failed enable restores the shared toggle flag"

"$ROOT/bin/monarch-menu" --tree | jq -e '
  .[] | select(.id == "setup.security.chat-privacy")
  | .action == "monarch-toggle-chat-privacy"
    and .checked == "! monarch-toggle-enabled chat-privacy-off"
' >/dev/null
pass "the Security menu exposes the chat masking state and action"
