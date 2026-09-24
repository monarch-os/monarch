#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/home"

cat >"$sandbox/bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CURL_CALLS"
exit 0
STUB
chmod +x "$sandbox/bin/curl"

if HOME="$sandbox/home" CURL_CALLS="$sandbox/curl-calls" PATH="$sandbox/bin:/usr/bin" \
  "$ROOT/bin/monarch-tui-install" Test btop tile --help >/dev/null 2>&1; then
  fail "tui install accepts an option-like icon reference"
fi
[[ ! -e $sandbox/curl-calls ]] || fail "tui install passes an invalid icon reference to curl"
pass "tui install rejects icon references that are neither files nor HTTP URLs"
