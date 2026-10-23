#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/state" "$temporary/home/.local/share/applications"
export TEST_STATE="$temporary/state"
export HOME="$temporary/home"
export PATH="$temporary/bin:/usr/bin:/bin"

cat >"$temporary/bin/pacman" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_STATE/log"
case "$*" in
  '-Qq')
    [[ ! -f $TEST_STATE/query-fail ]] || exit 2
    [[ ! -f $TEST_STATE/dua ]] || echo dua-cli
    [[ ! -f $TEST_STATE/disktree ]] || echo disktree-bin
    exit 0
    ;;
  '-S --needed --noconfirm disktree-bin')
    [[ ! -f $TEST_STATE/install-fail ]] || exit 42
    touch "$TEST_STATE/disktree"
    ;;
  '-Qq disktree-bin') [[ -f $TEST_STATE/disktree ]] && echo disktree-bin ;;
  '-Qk --quiet disktree-bin') [[ ! -f $TEST_STATE/broken ]] ;;
  '-R --noconfirm dua-cli')
    [[ ! -f $TEST_STATE/remove-fail ]] || exit 43
    rm "$TEST_STATE/dua"
    ;;
  *) exit 99 ;;
esac
SH

cat >"$temporary/bin/monarch-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == "disktree-bin" && -f $TEST_STATE/disktree ]]
SH
cat >"$temporary/bin/monarch-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "disktree" && ! -f $TEST_STATE/broken ]]
SH
chmod +x "$temporary/bin/"*

cat >"$temporary/bin/disktree" <<'SH'
#!/bin/bash
[[ $* == "--help" && ! -f $TEST_STATE/help-fail ]]
SH
chmod +x "$temporary/bin/disktree"

run_system() { bash "$ROOT/install/reconcile/disktree-system.sh"; }
run_user() { bash "$ROOT/install/reconcile/disktree-user.sh"; }

touch "$TEST_STATE/dua" "$TEST_STATE/install-fail"
status=0
run_system || status=$?
(( status != 0 )) && [[ -f $TEST_STATE/dua ]] || fail "failed install removed dua"
rm "$TEST_STATE/install-fail"
touch "$TEST_STATE/broken"
run_system >/dev/null 2>&1 && fail "broken replacement permitted retirement"
[[ -f $TEST_STATE/dua ]] || fail "broken replacement removed dua"
rm "$TEST_STATE/broken"
touch "$TEST_STATE/help-fail"
run_system >/dev/null 2>&1 && fail "unusable executable permitted retirement"
[[ -f $TEST_STATE/dua ]] || fail "unusable executable removed dua"
rm "$TEST_STATE/help-fail"
touch "$TEST_STATE/remove-fail"
run_system >/dev/null 2>&1 && fail "removal failure was hidden"
[[ -f $TEST_STATE/dua && -f $TEST_STATE/disktree ]] || fail "removal failure lost either tool"
rm "$TEST_STATE/remove-fail"
run_system
[[ ! -f $TEST_STATE/dua && -f $TEST_STATE/disktree ]] || fail "transition did not replace dua"
grep -qFx -- '-R --noconfirm dua-cli' "$TEST_STATE/log" || fail "transition used recursive/cascade removal"
pass "install and verification precede retirement; failures remain retryable"

: >"$TEST_STATE/log"
run_system
[[ $(cat "$TEST_STATE/log") == "-Qq" ]] || fail "reconciliation repeated package mutations"
rm "$TEST_STATE/disktree"
: >"$TEST_STATE/log"
run_system
[[ $(cat "$TEST_STATE/log") == "-Qq" ]] || fail "absent optional tool was reinstalled"
touch "$TEST_STATE/query-fail"
run_system >/dev/null 2>&1 && fail "package database errors were ignored"
rm "$TEST_STATE/query-fail"
pass "transition is idempotent and package database failures propagate"

launcher="$HOME/.local/share/applications/Disk Usage.desktop"
cat >"$temporary/stock.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Disk Usage
Comment=Inspect disk usage interactively
TryExec=dua
Exec=monarch-launch-tui --app-id=org.monarch.disk-usage dua interactive /
Icon=Disk Usage
Terminal=false
Categories=System;Filesystem;
DESKTOP
cp "$temporary/stock.desktop" "$launcher"
run_user
[[ -f $launcher ]] || fail "launcher removed before replacement exists"
touch "$TEST_STATE/disktree"
run_user
[[ ! -e $launcher ]] || fail "stock launcher was not retired"
run_user
cp "$temporary/stock.desktop" "$launcher"
echo '# custom' >>"$launcher"
run_user
[[ -f $launcher ]] || fail "custom launcher was removed"
rm "$launcher"
ln -s "$temporary/stock.desktop" "$launcher"
run_user
[[ -L $launcher && -f $temporary/stock.desktop ]] || fail "user-owned symlink was changed"
pass "only the exact stock launcher is retired, after replacement readiness"

grep -qF 'reconcile/disktree-system.sh' "$ROOT/install/reconcile/system.sh" || fail "system transition is not wired"
grep -qF 'reconcile/disktree-user.sh' "$ROOT/install/reconcile/user.sh" || fail "user transition is not wired"
