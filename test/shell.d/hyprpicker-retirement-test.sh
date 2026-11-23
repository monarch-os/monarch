#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

marker="$test_root/state/hyprpicker-removed"
installed="$test_root/installed"
log="$test_root/pacman.log"
mkdir -p "$test_root/bin"

grep -qxF 'sudo bash /usr/share/monarch/install/reconcile/hyprpicker.sh' "$ROOT/install/reconcile/system.sh" || fail "hyprpicker retirement is not pinned to the packaged runtime"
! grep -qF 'reconcile/hyprpicker.sh' "$ROOT/install/config/all.sh" || fail "fresh installs run hyprpicker retirement"
pass "hyprpicker retirement runs only during system reconciliation"

cat >"$test_root/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRPICKER_TEST_LOG"
case "$*" in
  '-Qq hyprpicker')
    if [[ -f $HYPRPICKER_TEST_INSTALLED ]]; then
      echo hyprpicker
    else
      echo "error: package 'hyprpicker' was not found" >&2
      exit 1
    fi
    ;;
  '-R --print hyprpicker')
    [[ ${HYPRPICKER_TEST_BLOCKED:-false} == "false" ]]
    ;;
  '-R --noconfirm hyprpicker')
    rm -f "$HYPRPICKER_TEST_INSTALLED"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$test_root/bin/pacman"

run_retirement() {
  MONARCH_HYPRPICKER_RETIREMENT_MARKER="$marker" \
    HYPRPICKER_TEST_INSTALLED="$installed" \
    HYPRPICKER_TEST_LOG="$log" \
    HYPRPICKER_TEST_BLOCKED="${HYPRPICKER_TEST_BLOCKED:-false}" \
    PATH="$test_root/bin:/usr/bin" \
    bash "$ROOT/install/reconcile/hyprpicker.sh"
}

touch "$installed"
run_retirement
[[ -f $marker && ! -e $installed ]] || fail "hyprpicker retirement removes the installed package"
grep -qxF -- '-R --noconfirm hyprpicker' "$log" || fail "hyprpicker retirement did not remove the package"
pass "hyprpicker retirement removes the installed package"

: >"$log"
run_retirement
[[ ! -s $log ]] || fail "completed hyprpicker retirement ran twice"
pass "completed hyprpicker retirement is idempotent"

rm -f "$marker"
: >"$log"
run_retirement
[[ -f $marker ]] || fail "absent hyprpicker package did not record retirement"
! grep -qF -- '-R --noconfirm hyprpicker' "$log" || fail "absent hyprpicker package was removed"
pass "absent hyprpicker package records retirement"

rm -f "$marker"
touch "$installed"
: >"$log"
HYPRPICKER_TEST_BLOCKED=true run_retirement 2>"$test_root/error"
[[ -f $marker && -f $installed ]] || fail "dependent hyprpicker package was not preserved"
grep -qF 'hyprpicker has dependents' "$test_root/error" || fail "dependent hyprpicker package gave no reason"
pass "hyprpicker with dependents is preserved"
