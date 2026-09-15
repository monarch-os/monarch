#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

marker="$test_root/state/fuzzel-removed"
installed="$test_root/installed"
log="$test_root/pacman.log"
mkdir -p "$test_root/bin"

grep -qF 'reconcile/fuzzel.sh' "$ROOT/install/reconcile/system.sh" || fail "system reconciliation does not retire Fuzzel"
! grep -qF 'reconcile/fuzzel.sh' "$ROOT/install/config/all.sh" || fail "fresh installs run Fuzzel retirement"
pass "Fuzzel retirement runs only during system reconciliation"

cat >"$test_root/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FUZZEL_TEST_LOG"
case "$*" in
  '-Qq fuzzel')
    if [[ -f $FUZZEL_TEST_INSTALLED ]]; then
      echo fuzzel
    else
      echo "error: package 'fuzzel' was not found" >&2
      exit 1
    fi
    ;;
  '-R --print fuzzel')
    [[ ${FUZZEL_TEST_BLOCKED:-false} == "false" ]]
    ;;
  '-R --noconfirm fuzzel')
    rm -f "$FUZZEL_TEST_INSTALLED"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$test_root/bin/pacman"

run_retirement() {
  MONARCH_FUZZEL_RETIREMENT_MARKER="$marker" \
    FUZZEL_TEST_INSTALLED="$installed" \
    FUZZEL_TEST_LOG="$log" \
    FUZZEL_TEST_BLOCKED="${FUZZEL_TEST_BLOCKED:-false}" \
    PATH="$test_root/bin:/usr/bin" \
    bash "$ROOT/install/reconcile/fuzzel.sh"
}

touch "$installed"
run_retirement
[[ -f $marker && ! -e $installed ]] || fail "Fuzzel retirement removes the installed package"
grep -qxF -- '-R --noconfirm fuzzel' "$log" || fail "Fuzzel retirement did not remove the package"
pass "Fuzzel retirement removes the installed package"

: >"$log"
run_retirement
[[ ! -s $log ]] || fail "completed Fuzzel retirement ran twice"
pass "completed Fuzzel retirement is idempotent"

rm -f "$marker"
: >"$log"
run_retirement
[[ -f $marker ]] || fail "absent Fuzzel package did not record retirement"
! grep -qF -- '-R --noconfirm fuzzel' "$log" || fail "absent Fuzzel package was removed"
pass "absent Fuzzel package records retirement"

rm -f "$marker"
touch "$installed"
: >"$log"
FUZZEL_TEST_BLOCKED=true run_retirement 2>"$test_root/error"
[[ -f $marker && -f $installed ]] || fail "dependent Fuzzel package was not preserved"
grep -qF 'Fuzzel has dependents' "$test_root/error" || fail "dependent Fuzzel package gave no reason"
pass "Fuzzel with dependents is preserved"
