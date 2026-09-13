#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEEDTEST="$ROOT/bin/monarch-network-speedtest"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sys/test0/statistics"

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"
  [[ $actual == "$expected" ]] || fail "$description" "Expected: $expected" "Actual:   $actual"
  pass "$description"
}

cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
printf '1.1.1.1 via 192.0.2.1 dev test0 src 192.0.2.2\n'
STUB

cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
if [[ $* == *api.fast.com* ]]; then
  printf '{}\n'
else
  exec /usr/bin/sleep 30
fi
STUB

cat >"$TMP/bin/jq" <<'STUB'
#!/bin/bash
cat >/dev/null
printf 'https://example.test/payload\n'
STUB

cat >"$TMP/bin/sleep" <<'STUB'
#!/bin/bash
printf '1150000\n' >"$SPEEDTEST_COUNTER"
STUB

cat >"$TMP/bin/awk" <<'STUB'
#!/bin/bash
set -o pipefail
if [[ $* == *BEGIN* ]]; then
  printf '%s\n' "${LC_ALL:-unset}" >>"$AWK_LOCALES"
  if [[ ${LC_ALL:-} != C ]]; then
    /usr/bin/awk "$@" | tr . ,
    exit $?
  fi
fi
exec /usr/bin/awk "$@"
STUB

chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:/usr/bin"
export MONARCH_SYS_NET="$TMP/sys"
export SPEEDTEST_COUNTER="$TMP/sys/test0/statistics/rx_bytes"
export AWK_LOCALES="$TMP/awk-locales"
printf '1000000\n' >"$SPEEDTEST_COUNTER"
: >"$AWK_LOCALES"

sample=$(LC_ALL=fr_FR.UTF-8 "$SPEEDTEST" down 1 2>"$TMP/stderr")
assert_equals "prints a protocol-safe decimal point under a comma locale" "$sample" "1.2"
assert_equals "runs both numeric conversions in the C locale" \
  "$(tr '\n' ' ' <"$AWK_LOCALES")" "C C "

echo
echo "All network speed test tests passed."
