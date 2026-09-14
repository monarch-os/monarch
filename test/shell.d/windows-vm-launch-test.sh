#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export MONARCH_WINDOWS_DIR="$test_tmp/runtime"
mkdir -p "$HOME"

source "$ROOT/bin/monarch-windows-vm"

trace="$test_tmp/trace"
rdp_ready=false

migrate_legacy_compose() { return 0; }
read_credential() {
  case $1 in
  USERNAME) printf 'docker' ;;
  PASSWORD) printf 'admin' ;;
  esac
}
ensure_krb5_config() { :; }
priv() { :; }
gum() { :; }
niri() { printf '{"logical":{"scale":1}}\n'; }
xfreerdp3() { :; }
nc() { $rdp_ready; }
monarch-notification-send() { printf '%s\n' "$*" >>"$trace"; }

launch_windows
grep -q 'Starting Windows VM.*This can take 15-30 seconds' "$trace" ||
  fail "a cold Windows launch announces the startup wait"
pass "a cold Windows launch announces the startup wait"

: >"$trace"
rdp_ready=true
launch_windows
[[ ! -s $trace ]] || fail "an already-ready Windows VM repeats the startup notification"
pass "an already-ready Windows VM connects without a startup notification"
