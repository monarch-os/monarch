#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

(( EUID != 0 )) || { echo "Run this fixture test unprivileged" >&2; exit 1; }
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export AUTH_TEST_TMP="$test_tmp"
python3 - "$ROOT" "$test_tmp" <<'PY'
from pathlib import Path
import sys
root, tmp = map(Path, sys.argv[1:])

def replace_fixture(text, old, new):
  assert text.count(old) == 1, f"fixture target changed: {old!r}"
  return text.replace(old, new)

# Run only the elevation preamble, never any reset function or cleanup trap.
source = (root / 'bin/monarch-system-factory-reset').read_text()
assert source.count('\nlog() {') == 1, 'reset preamble boundary changed'
text = source.split('\nlog() {')[0]
text = replace_fixture(text, '/usr/bin/monarch-system-factory-reset', str(tmp / 'packaged-reset'))
text = replace_fixture(text, '/usr/bin/sudo', str(tmp / 'sudo'))
text += '\nprintf "%s\\n" "$MONARCH_PATH" "$PATH" >"$AUTH_TEST_TMP/runtime"\n'
(tmp / 'checkout-reset').write_text(text)
(tmp / 'packaged-reset').write_text(text)
(tmp / 'root-preamble').write_text(replace_fixture(text, '(( EUID != 0 ))', '(( 0 != 0 ))'))
(tmp / 'sudo').write_text('''#!/bin/bash
printf '%s\\n' "$@" >"$AUTH_TEST_TMP/argv"
printf 'echo compromised\\n' >"$AUTH_TEST_TMP/checkout-reset"
''')
(tmp / 'sudo').chmod(0o755)
PY
MONARCH_PATH="$test_tmp/hostile" MONARCH_FACTORY_RESET_LIB_ONLY=true \
  bash "$test_tmp/checkout-reset" --fixture
mapfile -t args <"$test_tmp/argv"
[[ ${args[0]} == /usr/bin/env && ${args[-2]} == "$test_tmp/packaged-reset" && ${args[-1]} == --fixture ]] ||
  fail "elevation selected checkout code instead of the fixed package"
rm "$test_tmp/argv"
cp "$test_tmp/packaged-reset" "$test_tmp/checkout-reset"
echo '# divergent' >>"$test_tmp/checkout-reset"
if bash "$test_tmp/checkout-reset"; then
  fail "divergent checkout was elevated"
fi
[[ ! -e $test_tmp/argv ]] || fail "divergent checkout reached sudo"
# A fixture-only root branch avoids elevation and still runs no reset functions.
MONARCH_PATH="$test_tmp/hostile" MONARCH_FACTORY_RESET_LIB_ONLY=true bash "$test_tmp/root-preamble"
[[ $(cat "$test_tmp/runtime") == $'/usr/share/monarch\n/usr/bin:/usr/sbin' ]] || fail "root runtime accepts hostile environment"
pass "fixed elevation survives checkout replacement, rejects divergence and pins root environment"
