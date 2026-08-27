#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/install/helpers/workspaces.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

printf '%s' $'# Personal workspaces\n\n  Main  \nCode\nChat\nMail\nDocs\nMedia\nSeven\nEight\nNine\nTen\nIgnored\n' \
  >"$test_tmp/workspaces.conf"

names=(stale)
monarch_read_workspace_names "$test_tmp/workspaces.conf" names

(( ${#names[@]} == 10 )) || fail "workspace parser does not enforce the shortcut limit"
[[ ${names[0]} == "Main" ]] || fail "workspace parser does not trim names"
[[ ${names[9]} == "Ten" ]] || fail "workspace parser returned the wrong final name"
pass "workspace parser ignores comments, trims names, and caps the result"

names=(stale)
monarch_read_workspace_names "$test_tmp/missing.conf" names
(( ${#names[@]} == 0 )) || fail "missing workspace file does not return an empty result"
pass "workspace parser leaves fallback policy to its caller"
