#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
rules_dir="$TEST_ROOT/rules"
marker_dir="$TEST_ROOT/markers"
udev_control="$TEST_ROOT/udev-control"
udevadm="$TEST_ROOT/udevadm"
mkdir -p "$rules_dir"

cat >"$udevadm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$MONARCH_UDEVADM_LOG"
[[ ${MONARCH_UDEVADM_FAIL:-0} == 0 ]]
EOF
chmod +x "$udevadm"

run_reconcile() {
  MONARCH_UDEV_RULES_DIR="$rules_dir" \
    MONARCH_UDEV_MARKER_DIR="$marker_dir" \
    MONARCH_UDEV_CONTROL="$udev_control" \
    MONARCH_UDEVADM_COMMAND="$udevadm" \
    MONARCH_UDEVADM_LOG="$TEST_ROOT/udevadm.log" \
    MONARCH_UDEVADM_FAIL="${MONARCH_UDEVADM_FAIL:-0}" \
    bash "$ROOT/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
}

power_rule="$rules_dir/99-power-profile.rules"
wifi_rule="$rules_dir/99-wifi-powersave.rules"

cat >"$power_rule" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set power-saver"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set balanced"
EOF
run_reconcile
[[ -f $power_rule ]]

cat >"$power_rule" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile-battery --property=After=power-profiles-daemon.service /home/y0no/.local/share/monarch/bin/monarch-powerprofiles-set battery"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile-ac --property=After=power-profiles-daemon.service /home/y0no/.local/share/monarch/bin/monarch-powerprofiles-set ac"
EOF
run_reconcile
[[ ! -e $power_rule && ! -e $power_rule.monarch-disabled ]]

cat >"$power_rule" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile --property=After=power-profiles-daemon.service /tmp/source tree/bin/monarch-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile --property=After=power-profiles-daemon.service /tmp/source tree/bin/monarch-powerprofiles-set"
EOF
run_reconcile
[[ ! -e $power_rule ]]

cat >"$wifi_rule" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/home/y0no/.local/share/monarch/bin/monarch-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/home/y0no/.local/share/monarch/bin/monarch-wifi-powersave off"
EOF
run_reconcile
[[ ! -e $wifi_rule ]]

cat >"$wifi_rule" <<'EOF'
  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-wifi-powersave-on /srv/monarch checkout/bin/monarch-wifi-powersave on"
  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-wifi-powersave-off /srv/monarch checkout/bin/monarch-wifi-powersave off"
EOF
run_reconcile
[[ ! -e $wifi_rule ]]

cat >"$power_rule" <<'EOF'
# Locally modified legacy rule
SUBSYSTEM=="power_supply", \
  # A comment between continuations must not hide RUN
  ATTR{type}=="Mains", RUN{program}:=e"/opt/custom/bin/monarch-powerprofiles-set battery"
EOF
printf '%s\n' occupied >"$power_rule.monarch-disabled"
run_reconcile
[[ ! -e $power_rule ]]
[[ -f $power_rule.monarch-disabled.1 ]]
grep -qF '# Locally modified legacy rule' "$power_rule.monarch-disabled.1"

printf '%s\n' '# administrator rule' >"$wifi_rule"
run_reconcile
[[ -f $wifi_rule && ! -e $wifi_rule.monarch-disabled ]]

cat >"$wifi_rule" <<'EOF'
ENV{NOTE}="RUN+=\"/opt/bin/monarch-wifi-powersave on\""
SUBSYSTEM=="power_supply", ENV{NOTE}="local", # RUN+="/opt/bin/monarch-wifi-powersave on"
SUBSYSTEM=="power_supply", RUN+="/opt/bin/monarch-wifi-powersave-safe on"
EOF
run_reconcile
[[ -f $wifi_rule && ! -e $wifi_rule.monarch-disabled ]]

rm "$wifi_rule"
ln -s /dev/null "$wifi_rule"
run_reconcile
[[ -L $wifi_rule && $(readlink "$wifi_rule") == "/dev/null" ]]

rm "$wifi_rule"
ln -s /tmp/missing-legacy-rule "$wifi_rule"
run_reconcile
[[ ! -L $wifi_rule && -L $wifi_rule.monarch-disabled ]]

rm "$power_rule.monarch-disabled"
mkdir "$power_rule"
run_reconcile
[[ ! -e $power_rule && -d $power_rule.monarch-disabled ]]

mv "$power_rule.monarch-disabled" "$power_rule.monarch-disabled.2"
mkfifo "$power_rule"
run_reconcile
[[ ! -e $power_rule && -p $power_rule.monarch-disabled ]]

touch "$udev_control"
cat >"$wifi_rule" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/checkout/bin/monarch-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/checkout/bin/monarch-wifi-powersave off"
EOF
set +e
MONARCH_UDEVADM_FAIL=1 run_reconcile
reload_status=$?
set -e
((reload_status != 0))
[[ -f $marker_dir/99-wifi-powersave.rules.reload ]]
[[ ! -e $wifi_rule ]]
MONARCH_UDEVADM_FAIL=0 run_reconcile
[[ ! -e $marker_dir/99-wifi-powersave.rules.reload ]]
grep -qF 'control --reload' "$TEST_ROOT/udevadm.log"

cat >"$wifi_rule" <<'EOF'
SUBSYSTEM=="power_supply", RUN+="/checkout/bin/monarch-wifi-powersave on"
EOF
cat >"$TEST_ROOT/failing-install" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TEST_ROOT/failing-install"
set +e
MONARCH_UDEV_RULES_DIR="$rules_dir" \
  MONARCH_UDEV_MARKER_DIR="$marker_dir" \
  MONARCH_UDEV_CONTROL="$udev_control" \
  MONARCH_INSTALL_COMMAND="$TEST_ROOT/failing-install" \
  bash "$ROOT/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
marker_status=$?
set -e
((marker_status != 0))
[[ -f $wifi_rule ]]

cat >"$TEST_ROOT/churning-stat" <<'EOF'
#!/bin/bash
path=${!#}
[[ -e $path || -L $path ]] || exit 1
count=0
[[ ! -f $MONARCH_STAT_COUNT ]] || count=$(<"$MONARCH_STAT_COUNT")
printf '%s\n' "$((count + 1))" >"$MONARCH_STAT_COUNT"
printf '1:%s:regular file\n' "$((count % 2))"
EOF
chmod +x "$TEST_ROOT/churning-stat"
set +e
MONARCH_UDEV_RULES_DIR="$rules_dir" \
  MONARCH_UDEV_MARKER_DIR="$marker_dir" \
  MONARCH_UDEV_CONTROL="$udev_control" \
  MONARCH_STAT_COMMAND="$TEST_ROOT/churning-stat" \
  MONARCH_STAT_COUNT="$TEST_ROOT/stat-count" \
  bash "$ROOT/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
churn_status=$?
set -e
((churn_status != 0))
[[ -f $wifi_rule ]]

! grep -qF 'legacy-udev-rules.sh' "$ROOT/install/reconcile/system.sh"
grep -qF 'install/reconcile/schema/1-to-2/legacy-udev-rules.sh' \
  "$ROOT/install/reconcile/schema/1-to-2/system.sh"

echo "Legacy udev reconciliation checks pass"
