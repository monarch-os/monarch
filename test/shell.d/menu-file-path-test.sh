#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

menu_file="$ROOT/bin/monarch-menu-file"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work/-delete"

cat >"$sandbox/bin/find" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >"$FIND_ARGS"
STUB

cat >"$sandbox/bin/monarch-menu-select" <<'STUB'
#!/bin/bash
cat
STUB

chmod +x "$sandbox/bin/find" "$sandbox/bin/monarch-menu-select"

(
  cd "$sandbox/work"
  FIND_ARGS="$sandbox/find-args" PATH="$sandbox/bin:$PATH" \
    "$menu_file" "Pick file" -delete txt >/dev/null
)

first_arg=$(sed -n '1p' "$sandbox/find-args")
expected="<$sandbox/work/-delete>"
[[ $first_arg == "$expected" ]] ||
  fail "menu-file passes option-like roots to find as absolute paths" "expected: $expected\nactual:   $first_arg"
[[ -d $sandbox/work/-delete ]] || fail "menu-file never evaluates an option-like root"
pass "menu-file treats option-like roots as paths"
