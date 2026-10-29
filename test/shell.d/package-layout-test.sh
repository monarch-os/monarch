#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export LAYOUT_LOG="$test_tmp/removals"
export LAYOUT_SETTINGS_VERSION=2:2026.10.44-5
export LAYOUT_RUNTIME_VERSION=$LAYOUT_SETTINGS_VERSION
export LAYOUT_FILES=""

cat >"$test_tmp/pacman" <<'STUB'
#!/bin/bash
case "$*" in
  '-Qq monarch-settings')
    [[ $LAYOUT_SETTINGS_VERSION != missing ]] || exit 1
    printf 'monarch-settings\n'
    ;;
  '-Q monarch-settings')
    [[ $LAYOUT_SETTINGS_VERSION != missing ]] || exit 1
    printf 'monarch-settings %s\n' "$LAYOUT_SETTINGS_VERSION"
    ;;
  '-Qql monarch-settings')
    [[ ${LAYOUT_FILES_ERROR:-0} == 0 ]] || exit 1
    printf '%s' "$LAYOUT_FILES"
    ;;
  '-Q monarch')
    [[ $LAYOUT_RUNTIME_VERSION != missing ]] || exit 1
    printf 'monarch %s\n' "$LAYOUT_RUNTIME_VERSION"
    ;;
  '-R --noconfirm monarch-settings')
    printf '%s %s\n' "${MONARCH_UPDATE_PACMAN:-}" "$*" >>"$LAYOUT_LOG"
    exit "${LAYOUT_REMOVE_ERROR:-0}"
    ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$test_tmp/pacman"
sed "s|/usr/bin/pacman|$test_tmp/pacman|g" \
  "$ROOT/install/reconcile/package-layout.sh" >"$test_tmp/reconcile"

for LAYOUT_RUNTIME_VERSION in missing 2:2026.10.43-5 2:2026.10.44-4 2:2026.10.44-6 2026.10.44-5; do
  export LAYOUT_RUNTIME_VERSION
  : >"$LAYOUT_LOG"
  if bash "$test_tmp/reconcile" >"$test_tmp/output" 2>&1; then
    fail "an empty bridge was accepted with runtime $LAYOUT_RUNTIME_VERSION"
  fi
  [[ ! -s $LAYOUT_LOG ]] || fail "an unverified runtime allowed bridge removal"
done
pass "missing runtime and mismatched version, pkgrel or epoch prevent bridge removal"

export LAYOUT_RUNTIME_VERSION=$LAYOUT_SETTINGS_VERSION
bash "$test_tmp/reconcile"
[[ $(<"$LAYOUT_LOG") == '1 -R --noconfirm monarch-settings' ]] || fail "matching packages did not remove the empty bridge through the ALPM guard"
pass "matching complete versions allow empty-bridge removal"

: >"$LAYOUT_LOG"
LAYOUT_SETTINGS_VERSION=missing bash "$test_tmp/reconcile"
LAYOUT_FILES=/usr/share/monarch/default/config LAYOUT_RUNTIME_VERSION=missing bash "$test_tmp/reconcile"
[[ ! -s $LAYOUT_LOG ]] || fail "absent or nonempty settings triggered removal"
pass "absent settings and nonempty legacy settings remain no-ops"

if LAYOUT_FILES_ERROR=1 bash "$test_tmp/reconcile"; then
  fail "a failed file query was treated as an empty bridge"
fi
[[ ! -s $LAYOUT_LOG ]] || fail "a failed file query allowed removal"
if LAYOUT_REMOVE_ERROR=42 bash "$test_tmp/reconcile"; then
  fail "a failed removal reported success"
else
  status=$?
fi
(( status == 42 )) || fail "the removal failure status was lost"
pass "query and removal failures stop reconciliation"
