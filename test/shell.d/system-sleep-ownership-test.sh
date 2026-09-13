#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

helper="$ROOT/install/helpers/root-file.sh"
reconcile="$ROOT/install/reconcile/schema/1-to-2/system-sleep-ownership.sh"
[[ -f $helper ]] || fail "the root-file publisher is missing"
[[ -f $reconcile ]] || fail "the system-sleep ownership reconciliation is missing"

fake_bin="$test_tmp/bin"
sudo_log="$test_tmp/sudo.log"
mkdir -p "$fake_bin"
cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_LOG"
args=()
while (($#)); do
  case $1 in
    -o | -g)
      args+=("$1")
      shift
      if [[ $1 == root ]]; then
        [[ ${args[-1]} == -o ]] && args+=("$(id -u)") || args+=("$(id -g)")
      else
        args+=("$1")
      fi
      ;;
    *) args+=("$1") ;;
  esac
  shift
done
exec "${args[@]}"
STUB
cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
[[ ${SYSTEMCTL_FAIL:-0} == 0 ]]
STUB
chmod +x "$fake_bin/sudo" "$fake_bin/systemctl"

source "$helper"
publisher_root="$test_tmp/publisher-root"
publisher_source="$test_tmp/publisher-source"
publisher_target="$publisher_root/usr/lib/systemd/system-sleep/hook"
external_target="$test_tmp/external-target"
mkdir -p "${publisher_target%/*}"
printf '%s\n' replacement >"$publisher_source"
printf '%s\n' untouched >"$external_target"
ln -s "$external_target" "$publisher_target"

SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file "$publisher_source" "$publisher_target" 0755
[[ -f $publisher_target && ! -L $publisher_target ]] ||
  fail "the root-file publisher followed the destination symlink"
[[ $(<"$publisher_target") == replacement && $(<"$external_target") == untouched ]] ||
  fail "the root-file publisher changed content outside its destination"
[[ $(stat -c '%a' "$publisher_target") == 755 ]] ||
  fail "the root-file publisher did not apply the final mode before publication"
rg -q 'install -m 0755 .* -T .*\.monarch\.[[:alnum:]]{6}$' "$sudo_log" ||
  fail "the root-file publisher did not stage a sibling replacement"
rg -q 'mv -Tf -- .*\.monarch\.[[:alnum:]]{6} .*/hook$' "$sudo_log" ||
  fail "the root-file publisher did not atomically replace the destination"
pass "privileged files are prepared on a sibling inode and atomically published"

system_root="$test_tmp/system-root"
sleep_dir="$system_root/usr/lib/systemd/system-sleep"
drop_in_dir="$system_root/etc/systemd/system/supergfxd.service.d"
quarantine="$system_root/var/lib/monarch/reconcile/system-sleep-ownership"
mkdir -p "$sleep_dir" "$drop_in_dir"
chmod 0755 "$system_root" "$system_root/usr" "$system_root/usr/lib" \
  "$system_root/usr/lib/systemd" "$sleep_dir" "$system_root/etc" \
  "$system_root/etc/systemd" "$system_root/etc/systemd/system" "$drop_in_dir"

cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$sleep_dir/keyboard-backlight"
chmod 0775 "$sleep_dir/keyboard-backlight"
printf '%s\n' '# administrator force-igpu hook' >"$sleep_dir/force-igpu"
chmod 0755 "$sleep_dir/force-igpu"
external_drop_in="$test_tmp/custom-delay.conf"
printf '%s\n' '[Service]' 'ExecStartPre=/bin/sleep 20' >"$external_drop_in"
ln -s "$external_drop_in" "$drop_in_dir/delay-start.conf"

systemctl_log="$test_tmp/systemctl.log"
MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_PATH="$ROOT" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"

cmp "$ROOT/default/systemd/system-sleep/keyboard-backlight" \
  "$sleep_dir/keyboard-backlight" || fail "the unsafe keyboard hook was not repaired"
[[ $(stat -c '%a' "$sleep_dir/keyboard-backlight") == 755 ]] ||
  fail "the repaired keyboard hook is not executable"
[[ $(<"$sleep_dir/force-igpu") == '# administrator force-igpu hook' ]] ||
  fail "a trusted administrator hook was overwritten"
cmp "$ROOT/default/systemd/supergfxd.service.d/delay-start.conf" \
  "$drop_in_dir/delay-start.conf" || fail "the unsafe supergfxd drop-in was not repaired"
[[ $(<"$external_drop_in") == $'[Service]\nExecStartPre=/bin/sleep 20' ]] ||
  fail "the unsafe drop-in symlink target was modified"
find "$quarantine" -type l -lname "$external_drop_in" -print -quit | rg -q . ||
  fail "the unsafe custom drop-in was not preserved for administrator review"
[[ $(<"$systemctl_log") == 'daemon-reload' ]] ||
  fail "systemd was not reloaded after replacing its drop-in"
pass "V4 sleep files are repaired without overwriting trusted administrator changes"

MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_PATH="$ROOT" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ $(wc -l <"$systemctl_log") == 1 ]] ||
  fail "idempotent reconciliation reloaded systemd again"
pass "system-sleep ownership reconciliation is idempotent"

chmod 0664 "$drop_in_dir/delay-start.conf"
if MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_PATH="$ROOT" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" SYSTEMCTL_FAIL=1 \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"; then
  fail "a failed systemd reload reported a completed repair"
fi
[[ -e $quarantine/systemd-reload-needed ]] ||
  fail "a failed systemd reload did not leave a retry marker"

MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_PATH="$ROOT" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ ! -e $quarantine/systemd-reload-needed ]] ||
  fail "a successful retry did not clear the systemd reload marker"
[[ $(wc -l <"$systemctl_log") == 3 ]] ||
  fail "the pending systemd reload was not retried exactly once"
pass "a failed systemd reload remains retryable"

hibernation="$ROOT/bin/monarch-hibernation-setup"
hybrid="$ROOT/bin/monarch-toggle-hybrid-gpu"
! rg -q 'cp -p .*system-sleep|cp -p .*supergfxd' "$hibernation" "$hybrid" ||
  fail "a privileged sleep file still inherits user ownership"

hook_line=$(rg -n 'monarch_install_root_file .*keyboard-backlight' "$hibernation" | cut -d: -f1)
resume_line=$(rg -n 'echo "HOOKS\+=\(resume\)"' "$hibernation" | cut -d: -f1)
[[ -n $hook_line && -n $resume_line && $hook_line -lt $resume_line ]] ||
  fail "hibernation becomes complete before its sleep hook is safely published"

force_line=$(rg -n 'monarch_install_root_file .*force-igpu' "$hybrid" | cut -d: -f1)
delay_line=$(rg -n 'monarch_install_root_file .*delay-start\.conf' "$hybrid" | cut -d: -f1)
mode_line=$(rg -n -F 's/"mode": ".*"/"mode": "Integrated"/' "$hybrid" | tail -1 | cut -d: -f1)
[[ -n $force_line && -n $delay_line && -n $mode_line ]] ||
  fail "hybrid GPU setup is missing a safely published support file"
((force_line < mode_line && delay_line < mode_line)) ||
  fail "hybrid GPU mode changes before its support files are safely published"
pass "sleep support files are published before their configurations become active"

rg -q 'system-sleep-ownership\.sh' "$ROOT/install/reconcile/schema/1-to-2/system.sh" ||
  fail "the V4 system transition does not repair historical sleep files"
pass "the V4 system transition runs the ownership repair"
