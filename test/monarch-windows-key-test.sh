#!/bin/bash

# Exercises the OEM key reader against fake MSDM tables, so it needs neither the
# firmware table nor sudo. The real table is root-only; MONARCH_MSDM_PATH points
# the command at a fixture the test can read directly.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
KEY_CMD="$ROOT/bin/monarch-windows-key"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

PATH="$ROOT/bin:$PATH"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"

  if [[ $actual != "$expected" ]]; then
    fail "$description" "Expected: $expected" "Actual:   $actual"
  fi

  pass "$description"
}

# An MSDM table is a 36-byte ACPI header plus a 20-byte licensing structure; the
# key follows as plain ASCII, which is why grep alone gets it out.
write_msdm() {
  { head -c 56 /dev/zero; printf '%s' "$2"; } >"$1"
}

KEY="H7TFB-N4W6M-6QVGX-9CBTV-KHKQY"

write_msdm "$TMP/msdm" "$KEY"
assert_equals "prints the key strings finds" \
  "$(MONARCH_MSDM_PATH="$TMP/msdm" "$KEY_CMD")" "$KEY"

# strings is in binutils, not in base: the cat fallback is the path a minimal
# install actually takes.
cat >"$TMP/bin/strings" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$TMP/bin/strings"
assert_equals "falls back to cat when strings finds nothing" \
  "$(PATH="$TMP/bin:$PATH" MONARCH_MSDM_PATH="$TMP/msdm" "$KEY_CMD")" "$KEY"

write_msdm "$TMP/keyless" "no product key in here"
if err=$(MONARCH_MSDM_PATH="$TMP/keyless" "$KEY_CMD" 2>&1 >/dev/null); then
  fail "fails when the table carries no key"
fi
assert_equals "reports a table without a key" "$err" \
  "Firmware license table found, but no Windows product key could be extracted."

if err=$(MONARCH_MSDM_PATH="$TMP/absent" "$KEY_CMD" 2>&1 >/dev/null); then
  fail "fails when the machine has no MSDM table"
fi
assert_equals "reports firmware without a table" "$err" \
  "No Windows license key found in firmware."

write_msdm "$TMP/unreadable" "$KEY"
chmod 000 "$TMP/unreadable"
if err=$(MONARCH_MSDM_PATH="$TMP/unreadable" "$KEY_CMD" 2>&1 >/dev/null); then
  fail "elevates an unreadable custom MSDM path"
fi
assert_equals "custom unreadable paths never reach sudo" "$err" \
  "Refusing to elevate a custom Windows license path."
grep -qF 'if [[ $MSDM != "$DEFAULT_MSDM" || -r $MSDM ]]; then' "$KEY_CMD" ||
  fail "custom MSDM reads can fall through to sudo after validation"
pass "custom MSDM paths cannot race into the sudo branch"

printf '\nAll windows key tests passed.\n'
