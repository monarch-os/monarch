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
    [[ ! -f $TEST_STATE/dust ]] || echo dust
    [[ ! -f $TEST_STATE/disktree ]] || echo disktree-bin
    exit 0
    ;;
  '-Q -- disktree-bin') [[ -f $TEST_STATE/disktree ]] && echo 'disktree-bin 0.11.0-1' ;;
  '-S --noconfirm --needed -- disktree-bin')
    [[ ! -f $TEST_STATE/install-fail ]] || exit 42
    touch "$TEST_STATE/disktree"
    ;;
  '-Qk --quiet disktree-bin') [[ ! -f $TEST_STATE/broken ]] ;;
  '-R --noconfirm -- dua-cli')
    [[ ! -f $TEST_STATE/remove-fail ]] || exit 43
    rm "$TEST_STATE/dua"
    ;;
  '-R --noconfirm -- dust')
    [[ ! -f $TEST_STATE/remove-fail ]] || exit 43
    rm "$TEST_STATE/dust"
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

for helper in monarch-pkg-add monarch-pkg-drop monarch-pkg-missing; do
  ln -s "$ROOT/bin/$helper" "$temporary/bin/$helper"
done
cat >"$temporary/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$temporary/bin/sudo"

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
grep -qFx -- '-R --noconfirm -- dua-cli' "$TEST_STATE/log" || fail "transition used recursive/cascade removal"
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

touch "$TEST_STATE/dust"
touch "$TEST_STATE/install-fail"
run_system >/dev/null 2>&1 && fail "dust replacement install failure was hidden"
[[ -f $TEST_STATE/dust ]] || fail "failed replacement removed dust"
rm "$TEST_STATE/install-fail"
run_system
[[ -f $TEST_STATE/disktree && ! -f $TEST_STATE/dust ]] || fail "dust installation was not replaced"
grep -qFx -- '-R --noconfirm -- dust' "$TEST_STATE/log" || fail "dust retirement used recursive/cascade removal"
: >"$TEST_STATE/log"
run_system
[[ $(cat "$TEST_STATE/log") == "-Qq" ]] || fail "dust migration repeated package mutations"
pass "legacy dust installations are replaced by Disktree"
touch "$TEST_STATE/dua" "$TEST_STATE/dust"
run_system
[[ ! -f $TEST_STATE/dua && ! -f $TEST_STATE/dust ]] || fail "coexisting legacy tools were not retired"
touch "$TEST_STATE/dust" "$TEST_STATE/broken"
run_system >/dev/null 2>&1 && fail "broken replacement permitted dust retirement"
[[ -f $TEST_STATE/dust ]] || fail "broken replacement removed dust"
rm "$TEST_STATE/broken"
touch "$TEST_STATE/remove-fail"
run_system >/dev/null 2>&1 && fail "dust removal failure was hidden"
[[ -f $TEST_STATE/dust ]] || fail "failed removal lost dust"
rm "$TEST_STATE/remove-fail"
run_system
[[ ! -f $TEST_STATE/dust ]] || fail "dust retirement was not retried"
pass "coexisting legacy tools and failed dust retirement remain retryable"
rm "$TEST_STATE/disktree"

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

rm "$launcher"
cat >"$temporary/dust.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Name=Disk Usage
Comment=Disk Usage
Exec=xdg-terminal-exec --app-id=TUI.float -e bash -c 'dust -r; read -n 1 -s'
Terminal=false
Type=Application
Icon=$HOME/.local/share/applications/icons/Disk Usage.png
StartupNotify=true
DESKTOP
cp "$temporary/dust.desktop" "$launcher"
rm "$TEST_STATE/disktree"
run_user
[[ -f $launcher ]] || fail "dust launcher removed before replacement exists"
touch "$TEST_STATE/disktree"
run_user
[[ ! -e $launcher ]] || fail "legacy dust launcher was not retired"
cat >"$launcher" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Disk Usage
Exec=xdg-terminal-exec --app-id=TUI.float -e bash -c "dust -r; read -n 1 -s"
Terminal=false
Type=Application
Icon=disk-usage
StartupNotify=true
DESKTOP
run_user
[[ ! -e $launcher ]] || fail "packaged dust launcher was not retired"
cp "$temporary/dust.desktop" "$launcher"
echo '# custom' >>"$launcher"
run_user
[[ -f $launcher ]] || fail "custom dust launcher was removed"
pass "legacy dust launcher is retired safely after replacement readiness"

grep -qF 'reconcile/disktree-system.sh' "$ROOT/install/reconcile/system.sh" || fail "system transition is not wired"
grep -qF 'reconcile/disktree-user.sh' "$ROOT/install/reconcile/user.sh" || fail "user transition is not wired"
