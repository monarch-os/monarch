#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mock_bin="$test_root/bin"
marker="$test_root/var/lib/monarch/reconcile/cups-browsed-removed"
unit_link="$test_root/multi-user.target.wants/cups-browsed.service"
printers_conf="$test_root/printers.conf"
log="$test_root/actions.log"
output="$test_root/output"
mkdir -p "$mock_bin" "${unit_link%/*}"

cat >"$mock_bin/pacman" <<'EOF'
#!/bin/bash
printf 'pacman\t%s\n' "$*" >>"$CUPS_TEST_LOG"
case "$*" in
  '-Qq cups-browsed')
    if [[ $CUPS_TEST_QUERY_FAILS == true ]]; then
      echo 'error: database is inconsistent' >&2
      exit 1
    elif [[ $CUPS_TEST_INSTALLED == true ]]; then
      echo cups-browsed
    else
      echo "error: package 'cups-browsed' was not found" >&2
      exit 1
    fi
    ;;
  '-R --print cups-browsed') [[ $CUPS_TEST_BLOCKED == false ]] ;;
  '-R --noconfirm cups-browsed') [[ $CUPS_TEST_REMOVE_FAILS == false ]] ;;
  *) exit 2 ;;
esac
EOF
cat >"$mock_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$CUPS_TEST_LOG"
case $1 in
  show)
    [[ $CUPS_TEST_SYSTEMD_FAILS == false ]] || exit 1
    if [[ $CUPS_TEST_ACTIVE == true || $CUPS_TEST_ENABLED == true ]]; then
      echo loaded
    else
      echo not-found
    fi
    ;;
  *) : ;;
esac
EOF
cat >"$mock_bin/lpstat" <<'EOF'
#!/bin/bash
printf 'lpstat\t%s\n' "$*" >>"$CUPS_TEST_LOG"
case $1 in
  -v)
    [[ $CUPS_TEST_LPSTAT_FAILS == false ]] || {
      echo 'lpstat: scheduler unavailable' >&2
      exit 1
    }
    printf '%s\n' "$CUPS_TEST_QUEUES"
    ;;
  -o)
    [[ $CUPS_TEST_JOB_QUERY_FAILS != "$2" ]] || exit 1
    [[ " $CUPS_TEST_BUSY " != *" $2 "* ]] || printf '%s-1 user 1024\n' "$2"
    ;;
  -p) [[ " $CUPS_TEST_EXISTING " == *" $2 "* ]] ;;
  *) exit 2 ;;
esac
EOF
cat >"$mock_bin/cupsreject" <<'EOF'
#!/bin/bash
printf 'cupsreject\t%s\n' "$*" >>"$CUPS_TEST_LOG"
[[ $CUPS_TEST_REJECT_FAILS != "${*: -1}" ]]
EOF
cat >"$mock_bin/lpadmin" <<'EOF'
#!/bin/bash
printf 'lpadmin\t%s\n' "$*" >>"$CUPS_TEST_LOG"
[[ $CUPS_TEST_DELETE_FAILS != "${*: -1}" ]]
EOF
chmod +x "$mock_bin"/*

retirement="$ROOT/install/reconcile/cups-browsed.sh"

reset_case() {
  rm -f "$marker" "$unit_link" "$printers_conf" "$log" "$output"
  installed=true
  query_fails=false
  blocked=false
  remove_fails=false
  enabled=true
  active=true
  systemd_fails=false
  lpstat_fails=false
  queues=""
  busy=""
  existing=""
  job_query_fails=""
  reject_fails=""
  delete_fails=""
}

run_retirement() {
  CUPS_TEST_LOG="$log" \
    CUPS_TEST_INSTALLED="$installed" \
    CUPS_TEST_QUERY_FAILS="$query_fails" \
    CUPS_TEST_BLOCKED="$blocked" \
    CUPS_TEST_REMOVE_FAILS="$remove_fails" \
    CUPS_TEST_ENABLED="$enabled" \
    CUPS_TEST_ACTIVE="$active" \
    CUPS_TEST_SYSTEMD_FAILS="$systemd_fails" \
    CUPS_TEST_LPSTAT_FAILS="$lpstat_fails" \
    CUPS_TEST_QUEUES="$queues" \
    CUPS_TEST_BUSY="$busy" \
    CUPS_TEST_EXISTING="$existing" \
    CUPS_TEST_JOB_QUERY_FAILS="$job_query_fails" \
    CUPS_TEST_REJECT_FAILS="$reject_fails" \
    CUPS_TEST_DELETE_FAILS="$delete_fails" \
    MONARCH_CUPS_BROWSED_RETIREMENT_MARKER="$marker" \
    MONARCH_CUPS_BROWSED_UNIT_LINK="$unit_link" \
    MONARCH_CUPS_PRINTERS_CONF="$printers_conf" \
    PATH="$mock_bin:/usr/bin" \
    bash "$retirement" >"$output" 2>&1
}

reset_case
queues=$'device for Office: implicitclass://Office/\n'
queues+=$'device for Busy: implicitclass://Busy/\n'
queues+=$'device for -p: implicitclass://-p/\n'
queues+=$'device for Manual: ipp://192.0.2.2/ipp/print\n'
queues+='device for USB: usb://HP/Printer'
busy="Busy"
existing="Office Busy -p Manual USB"
run_retirement

grep -qxF $'systemctl\tdisable --now cups-browsed.service' "$log" ||
  fail "enabled discovery was not disabled and stopped"
grep -qxF $'lpadmin\t-x Office' "$log" || fail "idle generated queue was not removed"
grep -qxF $'cupsreject\t-r Automatic printer discovery has been removed from Monarch Busy' "$log" ||
  fail "busy generated queue was not closed to new jobs"
! grep -qE $'lpadmin\t-x (Busy|-p|Manual|USB)$' "$log" ||
  fail "retirement removed a busy, unsafe, or manually configured queue"
grep -qF "unsafe name" "$output" || fail "unsafe generated queue was not reported"
grep -qxF $'pacman\t-R --noconfirm cups-browsed' "$log" ||
  fail "cups-browsed package was not removed"
[[ -f $marker ]] || fail "successful retirement was not recorded"
disable_line=$(grep -n $'systemctl\tdisable --now' "$log" | cut -d: -f1)
remove_line=$(grep -n $'pacman\t-R --noconfirm' "$log" | cut -d: -f1)
((disable_line < remove_line)) || fail "package was removed before discovery stopped"
pass "retirement stops discovery and removes only idle generated queues"

: >"$log"
run_retirement
[[ ! -s $log ]] || fail "machine marker did not preserve a deliberate reinstall"
pass "machine marker makes retirement one-shot"

reset_case
installed=false
enabled=false
printf '%s\n' 'DeviceURI implicitclass://Orphan/' >"$printers_conf"
queues='device for Orphan: implicitclass://Orphan/'
existing='Orphan'
ln -s /usr/lib/systemd/system/cups-browsed.service "$unit_link"
run_retirement
grep -qxF $'systemctl\tdisable --now cups-browsed.service' "$log" ||
  fail "loaded discovery process was not stopped after package removal"
grep -qxF $'lpadmin\t-x Orphan' "$log" ||
  fail "package-absent state kept a generated queue"
[[ ! -e $unit_link ]] || fail "stale discovery enablement survived"
[[ -f $marker ]] || fail "package-absent state was not recorded"
! grep -q $'pacman\t-R ' "$log" || fail "an absent package was removed again"
pass "package-absent systems lose generated queues and stale enablement"

reset_case
query_fails=true
if run_retirement; then
  fail "retirement treated a package database error as package absence"
fi
grep -qxF $'systemctl\tdisable --now cups-browsed.service' "$log" ||
  fail "package query failure left discovery running"
[[ ! -e $marker ]] || fail "package query failure was recorded as complete"
pass "package query errors stay disabled and retryable"

reset_case
systemd_fails=true
if run_retirement; then
  fail "retirement ignored a systemd query failure"
fi
! grep -q $'pacman\t-Qq' "$log" ||
  fail "package state was queried before discovery was stopped"
[[ ! -e $marker ]] || fail "systemd query failure was recorded as complete"
pass "systemd query errors remain retryable"

reset_case
blocked=true
if run_retirement; then
  fail "dependency-blocked package retirement succeeded"
fi
grep -qxF $'systemctl\tdisable --now cups-browsed.service' "$log" ||
  fail "dependency failure left automatic discovery running"
[[ ! -e $marker ]] || fail "blocked removal was recorded as complete"
! grep -q $'pacman\t-R --noconfirm' "$log" || fail "blocked package was removed"
pass "dependency failure stops discovery and remains retryable"

reset_case
lpstat_fails=true
if run_retirement; then
  fail "retirement ignored an unreadable CUPS queue list"
fi
[[ ! -e $marker ]] || fail "unread queue list was recorded as complete"
! grep -q $'pacman\t-R --noconfirm' "$log" || fail "backend was removed without a queue list"
pass "CUPS query failure keeps the stopped backend for retry"

reset_case
queues='device for Office: implicitclass://Office/'
existing="Office"
delete_fails="Office"
if run_retirement; then
  fail "retirement ignored a generated queue deletion failure"
fi
[[ ! -e $marker ]] || fail "failed queue cleanup was recorded as complete"
! grep -q $'pacman\t-R --noconfirm' "$log" || fail "backend was removed with a live generated queue"
pass "queue deletion failure remains retryable"

reset_case
queues='device for Office: implicitclass://Office/'
existing="Office"
reject_fails="Office"
if run_retirement; then
  fail "retirement ignored a queue rejection failure"
fi
[[ ! -e $marker ]] || fail "failed queue rejection was recorded as complete"
! grep -q $'pacman\t-R --noconfirm' "$log" || fail "backend was removed while a queue accepted jobs"
pass "queue rejection failure remains retryable"

reset_case
queues='device for Office: implicitclass://Office/'
existing="Office"
job_query_fails="Office"
if run_retirement; then
  fail "retirement treated a failed job query as an idle queue"
fi
! grep -q $'lpadmin\t-x Office' "$log" || fail "queue with unknown job state was removed"
[[ ! -e $marker ]] || fail "failed job query was recorded as complete"
pass "unknown job state preserves the queue and backend"

reset_case
remove_fails=true
if run_retirement; then
  fail "retirement ignored package removal failure"
fi
[[ ! -e $marker ]] || fail "failed package removal was recorded as complete"
grep -qxF $'systemctl\tdisable --now cups-browsed.service' "$log" ||
  fail "package removal failure left discovery running"
pass "package removal failure stays disabled and retryable"

reset_case
mkdir -p "${marker%/*}"
external="$test_root/external-marker"
printf '%s\n' keep >"$external"
ln -s "$external" "$marker"
if run_retirement; then
  fail "symlinked retirement state was trusted"
fi
[[ $(<"$external") == keep ]] || fail "symlinked marker target was modified"
pass "retirement state cannot be redirected through a symlink"

grep -qxF cups "$ROOT/install/monarch-base.packages" || fail "CUPS was removed"
grep -qxF cups-filters "$ROOT/install/monarch-base.packages" || fail "CUPS filters were removed"
grep -qxF system-config-printer "$ROOT/install/monarch-base.packages" ||
  fail "Print Settings was removed"
! grep -qxF cups-browsed "$ROOT/install/monarch-base.packages" ||
  fail "cups-browsed remains required"
! grep -qF 'cups-browsed.service' "$ROOT/install/config/enable-services.sh" ||
  fail "fresh installs still enable cups-browsed"
[[ ! -e $ROOT/etc/cups/cups-browsed.conf ]] || fail "unsafe cups-browsed config remains"
grep -qF 'reconcile/cups-browsed.sh' "$ROOT/install/config/all.sh" ||
  fail "fresh installs do not record printer discovery retirement"
grep -qF 'reconcile/cups-browsed.sh' "$ROOT/install/reconcile/system.sh" ||
  fail "existing systems do not retire printer discovery"
pass "fresh installs keep manual printing without automatic discovery"
