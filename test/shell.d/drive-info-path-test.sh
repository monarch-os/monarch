#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work"
printf 'device' >"$sandbox/work/-drive"

cat >"$sandbox/bin/lsblk" <<'STUB'
#!/bin/bash
printf '%s\0' "$@" >>"$LSBLK_ARGS"
printf '\n' >>"$LSBLK_ARGS"
case " $* " in
  *" SIZE "*) printf '1G\n' ;;
  *" MODEL "*) printf 'Model\n' ;;
esac
STUB
chmod +x "$sandbox/bin/lsblk"

(
  cd "$sandbox/work"
  LSBLK_ARGS="$sandbox/lsblk-args" PATH="$sandbox/bin:/usr/bin" \
    "$ROOT/bin/monarch-drive-info" -drive >/dev/null
)

python3 - "$sandbox/lsblk-args" "$sandbox/work/-drive" <<'PY'
import sys

raw = open(sys.argv[1], "rb").read().splitlines()[0].split(b"\0")
args = [value.decode() for value in raw if value]
expected = ["-no", "PKNAME", "--", sys.argv[2]]
if args != expected:
    print(f"expected: {expected}\nactual:   {args}", file=sys.stderr)
    raise SystemExit(1)
PY
pass "drive info normalizes and protects an option-like path"
