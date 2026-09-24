#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work/-target"

cat >"$sandbox/bin/mkdir" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >"$MKDIR_ARGS"
exit 99
STUB
chmod +x "$sandbox/bin/mkdir"

(
  cd "$sandbox/work"
  MKDIR_ARGS="$sandbox/mkdir-args" PATH="$sandbox/bin:/usr/bin" \
    "$ROOT/bin/monarch-disk-speedtest" -target >/dev/null 2>&1 || true
)

mapfile -t args <"$sandbox/mkdir-args"
[[ ${args[0]} == "<-p>" && ${args[1]} == "<-->" && ${args[2]} == "<$sandbox/work/-target>" ]] ||
  fail "disk speedtest passes an option-like target before normalizing it" "actual: ${args[*]}"
pass "disk speedtest normalizes an option-like target directory"
