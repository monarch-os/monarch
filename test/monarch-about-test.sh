#!/bin/bash

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ABOUT="$ROOT/bin/monarch-launch-about"
failures=0

assert_equals() {
  local description=$1
  local actual=$2
  local expected=$3

  if [[ $actual == "$expected" ]]; then
    echo "ok - $description"
  else
    echo "not ok - $description (expected '$expected', got '$actual')"
    ((failures++))
  fi
}

assert_equals "wide terminals use the full layout" \
  "$(COLUMNS=104 LINES=30 "$ABOUT" --layout)" "full"
assert_equals "narrow terminals use the compact layout" \
  "$(COLUMNS=103 LINES=40 "$ABOUT" --layout)" "compact"
assert_equals "short terminals use the compact layout" \
  "$(COLUMNS=140 LINES=29 "$ABOUT" --layout)" "compact"

if (( failures > 0 )); then
  echo
  echo "$failures test(s) failed."
  exit 1
fi

echo
echo "All About tests passed."
