#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export test_tmp XDG_RUNTIME_DIR="$test_tmp/runtime"
export PATH="$ROOT/bin:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

noctalia() {
  case "$*" in
    'msg nightlight-force-toggle')
      printf '%s\n' "$((1 - $(<"$test_tmp/nightlight")))" >"$test_tmp/nightlight"
      ;;
    'msg caffeine-enable') printf '1\n' >"$test_tmp/caffeine" ;;
    'msg caffeine-disable') printf '0\n' >"$test_tmp/caffeine" ;;
    *) return 99 ;;
  esac
}
monarch-refresh-config() { :; }
pkill() {
  [[ $* == '-x noctalia' ]] || return 99
  printf '0\n' >"$test_tmp/nightlight"
  printf '0\n' >"$test_tmp/caffeine"
}
pgrep() { return 1; }
setsid() { :; }
export -f noctalia monarch-refresh-config pkill pgrep setsid

for command in refresh restart; do
  printf '0\n' >"$test_tmp/nightlight"
  printf '0\n' >"$test_tmp/caffeine"
  monarch-toggle-nightlight on
  monarch-toggle-idle on
  "monarch-$command-noctalia"
  [[ ! -e $XDG_RUNTIME_DIR/monarch/nightlight && ! -e $XDG_RUNTIME_DIR/monarch/caffeine ]] ||
    fail "$command must clear the previous shell's toggle state"
  monarch-toggle-nightlight off
  [[ $(<"$test_tmp/nightlight") == 0 ]] || fail "$command must not invert nightlight off"
  monarch-toggle-idle on
  [[ $(<"$test_tmp/caffeine") == 1 ]] || fail "$command must let idle on reenable inhibition"
  monarch-toggle-idle status | jq -e '.enabled' >/dev/null
  monarch-toggle-nightlight status | jq -e '.enabled == false' >/dev/null
  monarch-toggle-idle off
  pass "$command keeps the shell and toggle indicators consistent"
done
