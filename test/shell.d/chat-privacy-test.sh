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

"$toggle" status | jq -e '.enabled == false' >/dev/null
"$toggle" init
[[ $(<"$state") == "include \"$rules\"" ]]
"$toggle" status | jq -e '.enabled == true' >/dev/null
pass "fresh installations enable chat masking"

"$toggle" off
[[ -f $state && ! -s $state ]]
"$toggle" init
[[ ! -s $state ]]
"$toggle" status | jq -e '.enabled == false' >/dev/null
"$toggle" on
"$toggle" toggle
[[ ! -s $state ]]
"$toggle" toggle
[[ $(<"$state") == "include \"$rules\"" ]]
pass "the toggle persists off across reconciliation and restores masking"

"$ROOT/bin/monarch-menu" --tree | jq -e '
  .[] | select(.id == "setup.security.chat-privacy")
  | .action == "monarch-toggle-chat-privacy"
    and (.checked | contains("monarch-toggle-chat-privacy status"))
' >/dev/null
pass "the Security menu exposes the chat masking state and action"
