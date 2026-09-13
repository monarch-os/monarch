#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/test"
cp "$ROOT/test/run" "$test_tmp/test/run"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/test/pass-test.sh"
printf '#!/bin/bash\nexit 7\n' >"$test_tmp/test/fail-test.sh"
printf 'path\tfeature\trisk\tenvironment\ntest/pass-test.sh\trunner\tlow\tisolated\ntest/fail-test.sh\trunner\tlow\tnetwork\n' \
  >"$test_tmp/test/suite.tsv"

run_suite() {
  status=0
  bash "$test_tmp/test/run" "$@" >"$test_tmp/output" 2>&1 || status=$?
}

for mode in focused invalid-mode; do
  run_suite "$mode"
  (( status == 2 )) || fail "$mode without a valid selection must return a usage error"
  if grep -q '0 failures' "$test_tmp/output"; then
    fail "$mode must not report an empty successful suite"
  fi
done
pass "invalid selections fail without reporting success"

run_suite focused test/missing-test.sh
(( status == 2 )) || fail "unknown tests must be rejected"
pass "focused mode rejects unknown tests"

run_suite focused test/pass-test.sh
(( status == 0 )) || fail "focused mode must run the selected test"
grep -q '1 tests, 0 failures' "$test_tmp/output" || fail "focused mode must report its test"
run_suite integration
(( status == 0 )) || fail "integration must exclude the network test"
grep -q '1 tests, 0 failures' "$test_tmp/output" || fail "integration must report its test"
pass "valid selections run the expected tests"

run_suite full
(( status == 1 )) || fail "a failing child must fail the suite"
grep -q '2 tests, 1 failures' "$test_tmp/output" || fail "full mode must report the failure"
pass "full mode propagates child failures"
