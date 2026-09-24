#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin"

cat >"$sandbox/bin/nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NM_CALLS"
case "$*" in
  *"SIGNAL,SECURITY,SSID dev wifi list"*) printf '80:WPA2:-n\n' ;;
  *"-g NAME connection show"*) printf '%s' "$NM_SAVED" ;;
  *"connection delete"*|*"dev wifi connect"*) exit 0 ;;
esac
STUB

cat >"$sandbox/bin/gum" <<'STUB'
#!/bin/bash
case $1 in
  choose) grep -F -- '-n' | sed -n '1p' ;;
  input) printf 'called\n' >>"$GUM_INPUT_CALLS"; printf 'secret\n' ;;
  spin)
    while (($#)) && [[ $1 != "--" ]]; do shift; done
    shift
    "$@"
    ;;
  confirm) exit 1 ;;
esac
STUB

chmod +x "$sandbox/bin/nmcli" "$sandbox/bin/gum"
export PATH="$sandbox/bin:$ROOT/bin:/usr/bin"
export NM_CALLS="$sandbox/nm-calls" GUM_INPUT_CALLS="$sandbox/gum-input" NM_SAVED=$'-n\n'
: >"$NM_CALLS"
: >"$GUM_INPUT_CALLS"

"$ROOT/bin/monarch-wifi-connect" >/dev/null
[[ ! -s $GUM_INPUT_CALLS ]] || fail "wifi connect treats an option-like saved SSID as a grep option"
pass "wifi connect matches an option-like saved SSID literally"

: >"$NM_CALLS"
"$ROOT/bin/monarch-wifi-forget" -n
grep -Fq -- 'connection delete id -n' "$NM_CALLS" ||
  fail "wifi forget does not delete an option-like saved SSID"
pass "wifi forget matches an option-like saved SSID literally"
