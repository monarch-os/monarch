#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
export MONARCH_USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
export MONARCH_SYSTEMD_USER_VENDOR_DIR="$test_tmp/usr/lib/systemd/user"
export TEST_SYSTEMCTL_LOG="$test_tmp/systemctl.log"
export TEST_SYSTEMCTL_RESTART_FAILURE="$test_tmp/restart-failure"
export PATH="$test_tmp/bin:/usr/bin"

mkdir -p "$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants" \
  "$MONARCH_USER_SYSTEMD_DIR/timers.target.wants" \
  "$MONARCH_SYSTEMD_USER_VENDOR_DIR" "$HOME/.config/monarch/extensions" \
  "$HOME/.config/monarch/hooks/theme-set.d" "$test_tmp/bin"

cat >"$test_tmp/bin/systemctl" <<'EOF'
#!/bin/bash

[[ $1 == "--user" ]]
shift

if [[ ${1:-} == "--runtime" ]]; then
  runtime=true
  shift
else
  runtime=false
fi

command=$1
shift
printf '%s %s%s\n' "$command" "$([[ $runtime == "true" ]] && printf '%s' '--runtime ')" "$*" >>"$TEST_SYSTEMCTL_LOG"

case $command in
  is-enabled)
    case $1 in
      monarch-recover-internal-monitor.service | monarch-battery-monitor.timer)
        printf '%s\n' enabled
        ;;
      monarch-battery-monitor.service)
        printf '%s\n' static
        ;;
    esac
    ;;
  is-active)
    case $1 in
      monarch-recover-internal-monitor.service)
        printf '%s\n' failed
        exit 3
        ;;
      monarch-battery-monitor.timer)
        printf '%s\n' active
        ;;
      monarch-battery-monitor.service)
        printf '%s\n' inactive
        exit 3
        ;;
    esac
    ;;
  reenable)
    case $1 in
      monarch-recover-internal-monitor.service)
        link="$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants/$1"
        ;;
      monarch-battery-monitor.timer)
        link="$MONARCH_USER_SYSTEMD_DIR/timers.target.wants/$1"
        ;;
      *) exit 1 ;;
    esac
    ln -sfn "$MONARCH_SYSTEMD_USER_VENDOR_DIR/$1" "$link"
    ;;
  restart)
    if [[ ${TEST_SYSTEMCTL_FAIL_RESTART_ONCE:-false} == "true" && \
      ! -f $TEST_SYSTEMCTL_RESTART_FAILURE ]]; then
      touch "$TEST_SYSTEMCTL_RESTART_FAILURE"
      exit 1
    fi
    ;;
  daemon-reload) ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_tmp/bin/systemctl"

recover_unit="$MONARCH_USER_SYSTEMD_DIR/monarch-recover-internal-monitor.service"
battery_unit="$MONARCH_USER_SYSTEMD_DIR/monarch-battery-monitor.service"
battery_timer="$MONARCH_USER_SYSTEMD_DIR/monarch-battery-monitor.timer"
menu="$HOME/.config/monarch/extensions/menu.sh"
theme_sample="$HOME/.config/monarch/hooks/theme-set.d/show-theme-notification.sample"

cat >"$recover_unit" <<'EOF'
[Unit]
Description=Monarch — recover the laptop display when an external monitor is unplugged
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/share/monarch/bin/monarch-hw-recover-internal-monitor
Restart=on-failure
RestartSec=2
LogLevelMax=warning

[Install]
WantedBy=graphical-session.target
EOF
cat >"$battery_unit" <<'EOF'
[Unit]
Description=Monarch Battery Monitor Check
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/share/monarch/bin/monarch-battery-monitor
Environment=DISPLAY=:0
LogLevelMax=warning
EOF
truncate -s -1 "$battery_unit"
cat >"$battery_timer" <<'EOF'
[Unit]
Description=Monarch Battery Monitor Timer
Requires=monarch-battery-monitor.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=30sec
AccuracySec=10sec

[Install]
WantedBy=timers.target
EOF
truncate -s -1 "$battery_timer"

cat >"$menu" <<'EOF'
# Overwrite parts of the monarch-menu with user-specific submenus.
# See $MONARCH_PATH/bin/monarch-menu for functions that can be overwritten.
#
# WARNING: Overwritten functions will obviously not be updated when Monarch changes.
#
# Example of minimal system menu:
#
# show_system_menu() {
#   case $(menu "System" "  Lock\n󰐥  Shutdown") in
#   *Lock*) monarch-system-lock ;;
#   *Shutdown*) monarch-system-shutdown ;;
#   *) back_to show_main_menu ;;
#   esac
# }
#
# Example of overriding just the about menu action: (Using zsh instead of bash (default))
#
# show_about() {
#   exec monarch-launch-or-focus-tui "zsh -c 'fastfetch; read -k 1'"
# }
EOF
cat >"$theme_sample" <<'EOF'
#!/bin/bash

# This hook is called with the snake-cased name of the theme that has just been set.
# To put it into use, remove .sample from the name.

# Example: Show the name of the theme that was just set.
# notify-send -u low "New theme" "Your new theme is $1"
EOF

for unit in "$recover_unit" "$battery_unit" "$battery_timer"; do
  cp "$ROOT/default/systemd/user/${unit##*/}" \
    "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${unit##*/}"
done
ln -s "../${recover_unit##*/}" \
  "$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants/${recover_unit##*/}"
ln -s "../${battery_timer##*/}" \
  "$MONARCH_USER_SYSTEMD_DIR/timers.target.wants/${battery_timer##*/}"

[[ $(sha256sum "$recover_unit" | cut -d' ' -f1) == "a60226f83b010601daa675cec6dd065851e3cf6cd66176cc5df687420bf0e1fc" ]]
[[ $(sha256sum "$battery_unit" | cut -d' ' -f1) == "f8a2f9a09f9b189c1d49e39e00bd74e010b2f7323c27f451878d3ce581d66a1c" ]]
[[ $(sha256sum "$battery_timer" | cut -d' ' -f1) == "e073738fdaadb814f04fcf9be55ac99a167f6c863d494da5b67b65d87d209761" ]]
[[ $(sha256sum "$menu" | cut -d' ' -f1) == "39f459e47012c9a6c827fa1b52bfeb57b2e84b2e614f3a490dd48f35cbffd974" ]]
[[ $(sha256sum "$theme_sample" | cut -d' ' -f1) == "85de7c0a6f12ae796663c409ad198d15d20d254a1444db66e0680ab7326f826e" ]]

cp "$recover_unit" "$test_tmp/v4-recover.service"
cp "$battery_unit" "$test_tmp/v4-battery.service"

bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh"

[[ ! -e $recover_unit && ! -e $battery_unit && ! -e $battery_timer ]]
[[ ! -e $menu && ! -e $theme_sample ]]
[[ $(readlink "$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants/${recover_unit##*/}") == "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${recover_unit##*/}" ]]
[[ $(readlink "$MONARCH_USER_SYSTEMD_DIR/timers.target.wants/${battery_timer##*/}") == "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${battery_timer##*/}" ]]
grep -qx 'ExecStart=/usr/bin/monarch-hw-recover-internal-monitor' \
  "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${recover_unit##*/}"
grep -qx 'ExecStart=/usr/bin/monarch-battery-monitor' \
  "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${battery_unit##*/}"
grep -qx 'daemon-reload ' "$TEST_SYSTEMCTL_LOG"
grep -qx 'reenable monarch-recover-internal-monitor.service' "$TEST_SYSTEMCTL_LOG"
grep -qx 'reenable monarch-battery-monitor.timer' "$TEST_SYSTEMCTL_LOG"
! grep -q '^reenable monarch-battery-monitor.service$' "$TEST_SYSTEMCTL_LOG"
grep -qx 'restart monarch-recover-internal-monitor.service' "$TEST_SYSTEMCTL_LOG"
grep -qx 'restart monarch-battery-monitor.timer' "$TEST_SYSTEMCTL_LOG"
! grep -q '^restart monarch-battery-monitor.service$' "$TEST_SYSTEMCTL_LOG"
[[ ! -e $HOME/.local/state/monarch/reconcile/1-to-2/legacy-user-files ]]

: >"$TEST_SYSTEMCTL_LOG"
bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh"
[[ ! -s $TEST_SYSTEMCTL_LOG ]]

printf '%s\n' '# custom battery monitor' >"$battery_unit"
printf '%s\n' '# custom menu' >"$menu"
printf '%s\n' '# custom hook sample' >"$theme_sample"
ln -s "$test_tmp/custom-recovery.service" "$recover_unit"
: >"$TEST_SYSTEMCTL_LOG"

bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh"

[[ $(<"$battery_unit") == "# custom battery monitor" ]]
[[ $(<"$menu") == "# custom menu" ]]
[[ $(<"$theme_sample") == "# custom hook sample" ]]
[[ -L $recover_unit && $(readlink "$recover_unit") == "$test_tmp/custom-recovery.service" ]]
[[ ! -s $TEST_SYSTEMCTL_LOG ]]

rm -f "$recover_unit"
cp "$test_tmp/v4-recover.service" "$recover_unit"
ln -sfn "../${recover_unit##*/}" \
  "$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants/${recover_unit##*/}"
: >"$TEST_SYSTEMCTL_LOG"
export TEST_SYSTEMCTL_FAIL_RESTART_ONCE=true

if bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh"; then
  fail "a failed unit restart did not stop reconciliation"
fi

unit_marker="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-user-files/${recover_unit##*/}"
[[ -f $unit_marker ]] || fail "a failed unit restart lost its retry state"
[[ ! -e $recover_unit ]] || fail "a failed unit restart restored the legacy override"

bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh"

[[ ! -e $unit_marker ]]
[[ $(readlink "$MONARCH_USER_SYSTEMD_DIR/graphical-session.target.wants/${recover_unit##*/}") == "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${recover_unit##*/}" ]]
(( $(grep -xc 'daemon-reload ' "$TEST_SYSTEMCTL_LOG") == 2 ))
(( $(grep -xc 'reenable monarch-recover-internal-monitor.service' "$TEST_SYSTEMCTL_LOG") == 2 ))
(( $(grep -xc 'restart monarch-recover-internal-monitor.service' "$TEST_SYSTEMCTL_LOG") == 2 ))

unset TEST_SYSTEMCTL_FAIL_RESTART_ONCE
cp "$test_tmp/v4-battery.service" "$battery_unit"
rm "$MONARCH_SYSTEMD_USER_VENDOR_DIR/${battery_unit##*/}"
: >"$TEST_SYSTEMCTL_LOG"

if bash "$ROOT/install/reconcile/schema/1-to-2/legacy-user-files.sh" >/dev/null 2>&1; then
  fail "a missing packaged unit allowed legacy cleanup"
fi

cmp "$test_tmp/v4-battery.service" "$battery_unit"
[[ ! -s $TEST_SYSTEMCTL_LOG ]]
[[ ! -e $HOME/.local/state/monarch/reconcile/1-to-2/legacy-user-files/${battery_unit##*/} ]]

pass "stock v4 user files adopt packaged units without changing custom files"
