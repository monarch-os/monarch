#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

helper="$ROOT/install/helpers/root-file.sh"
reconcile="$ROOT/install/reconcile/system-sleep-ownership.sh"
[[ -f $helper ]] || fail "the root-file publisher is missing"
[[ -f $reconcile ]] || fail "the system-sleep ownership reconciliation is missing"

fake_bin="$test_tmp/bin"
sudo_log="$test_tmp/sudo.log"
mkdir -p "$fake_bin"
cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_LOG"
exit 99
STUB
cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
[[ ${SYSTEMCTL_FAIL:-0} == 0 ]]
STUB
chmod +x "$fake_bin/sudo" "$fake_bin/systemctl"

source "$helper"
publisher_root="$test_tmp/publisher-root"
publisher_runtime="$publisher_root/usr/share/monarch"
publisher_source="$publisher_runtime/default/systemd/system-sleep/keyboard-backlight"
publisher_target="$publisher_root/usr/lib/systemd/system-sleep/keyboard-backlight"
external_target="$test_tmp/external-target"
mkdir -p "${publisher_source%/*}" "${publisher_target%/*}"
printf '%s\n' replacement >"$publisher_source"
printf '%s\n' untouched >"$external_target"
ln -s "$external_target" "$publisher_target"

MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight
[[ -f $publisher_target && ! -L $publisher_target ]] ||
  fail "the root-file publisher followed the destination symlink"
[[ $(<"$publisher_target") == replacement && $(<"$external_target") == untouched ]] ||
  fail "the root-file publisher changed content outside its destination"
[[ $(stat -c '%a' "$publisher_target") == 755 ]] ||
  fail "the root-file publisher did not apply the final mode before publication"
[[ ! -s $sudo_log ]] || fail "test-root publication reached sudo"
pass "privileged files are prepared on a sibling inode and atomically published"

before=$(sha256sum "$publisher_target")
chmod 0777 "${publisher_target%/*}"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight; then
  fail "the root-file publisher accepted a writable destination parent"
fi
chmod 0755 "${publisher_target%/*}"
[[ $(sha256sum "$publisher_target") == "$before" ]] ||
  fail "a rejected destination parent changed the published file"

publisher_parent=${publisher_target%/*}
mv "$publisher_parent" "$publisher_parent.trusted"
mkdir "$publisher_parent.external"
ln -s "$publisher_parent.external" "$publisher_parent"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight; then
  fail "the root-file publisher accepted a symlinked destination parent"
fi
[[ ! -e $publisher_parent.external/keyboard-backlight ]] ||
  fail "publication through a rejected parent changed its symlink target"
unlink "$publisher_parent"
mv "$publisher_parent.trusted" "$publisher_parent"

chmod 0777 "${publisher_source%/*}"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight; then
  fail "the root-file publisher accepted a writable packaged source parent"
fi
chmod 0755 "${publisher_source%/*}"

mv "$publisher_source" "$publisher_source.packaged"
ln -s "$external_target" "$publisher_source"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight; then
  fail "the root-file publisher accepted a symlinked packaged source"
fi
unlink "$publisher_source"
mv "$publisher_source.packaged" "$publisher_source"

hostile_runtime="$publisher_root/hostile-runtime"
mkdir -p "$hostile_runtime/default/systemd/system-sleep"
printf '%s\n' hostile >"$hostile_runtime/default/systemd/system-sleep/keyboard-backlight"
MONARCH_PATH="$hostile_runtime" MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file keyboard-backlight
[[ $(<"$publisher_target") == replacement ]] ||
  fail "MONARCH_PATH selected the privileged publisher payload"

if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file unknown; then
  fail "the root-file publisher accepted an unknown asset"
fi

cp "$ROOT/default/systemd/system-sleep/force-igpu" \
  "$publisher_runtime/default/systemd/system-sleep/force-igpu"
MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_install_root_file force-igpu
MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_remove_root_file force-igpu
[[ ! -e $publisher_parent/force-igpu && ! -L $publisher_parent/force-igpu ]] ||
  fail "the root-file remover left its allowlisted file behind"
mkdir "$publisher_parent/force-igpu"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_remove_root_file force-igpu; then
  fail "the root-file remover recursively removed an unexpected directory"
fi
[[ -d $publisher_parent/force-igpu ]] || fail "a rejected directory was removed"
rm -d "$publisher_parent/force-igpu"
printf '%s\n' '# administrator hook' >"$publisher_parent/force-igpu"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_remove_root_file force-igpu; then
  fail "the root-file remover deleted a customized regular file"
fi
[[ $(<"$publisher_parent/force-igpu") == '# administrator hook' ]] ||
  fail "a customized regular file changed during removal"
rm "$publisher_parent/force-igpu"
ln -s "$external_target" "$publisher_parent/force-igpu"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  SUDO_LOG="$sudo_log" PATH="$fake_bin:/usr/bin" \
  monarch_remove_root_file force-igpu; then
  fail "the root-file remover deleted an administrator symlink"
fi
[[ -L $publisher_parent/force-igpu && $(<"$external_target") == untouched ]] ||
  fail "an administrator symlink changed during removal"

publisher_delay_source="$publisher_runtime/default/systemd/supergfxd.service.d/delay-start.conf"
publisher_delay="$publisher_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
mkdir -p "${publisher_delay_source%/*}" "${publisher_delay%/*}"
cp "$ROOT/default/systemd/supergfxd.service.d/delay-start.conf" "$publisher_delay_source"
MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  monarch_install_root_file delay-start
MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  monarch_remove_root_file delay-start
printf '%s\n' '[Service]' 'ExecStartPre=/bin/sleep 30' >"$publisher_delay"
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  monarch_remove_root_file delay-start; then
  fail "the root-file remover deleted a customized service drop-in"
fi
grep -Fqx 'ExecStartPre=/bin/sleep 30' "$publisher_delay" ||
  fail "a customized service drop-in changed during removal"
[[ ! -s $sudo_log ]] || fail "test-root removal reached sudo"
pass "root-file publication rejects untrusted paths and non-allowlisted assets"

publisher_config="$publisher_root/etc/supergfxd.conf"
mkdir -p "${publisher_config%/*}"
printf '%s\n' '{' '  "mode": "Hybrid",' '  "vfio_enable": false' '}' >"$publisher_config"
chmod 0640 "$publisher_config"
config_inode=$(stat -c '%i' "$publisher_config")
MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  monarch_configure_supergfxd Integrated
grep -Eq '"mode"[[:space:]]*:[[:space:]]*"Integrated"' "$publisher_config" ||
  fail "the staged supergfxd configuration did not enable Integrated mode"
grep -Eq '"vfio_enable"[[:space:]]*:[[:space:]]*true' "$publisher_config" ||
  fail "the staged supergfxd configuration did not enable Vfio"
[[ $(stat -c '%a' "$publisher_config") == 640 && $(stat -c '%i' "$publisher_config") != "$config_inode" ]] ||
  fail "supergfxd configuration was not atomically replaced with its original mode"

printf '%s\n' '{' '  "mode": "Hybrid",' '  "vfio_enable": 0' '}' >"$publisher_config"
config_before=$(sha256sum "$publisher_config")
if MONARCH_ROOT_FILE_TEST_ROOT="$publisher_root" \
  MONARCH_ROOT_FILE_TEST_RUNTIME="$publisher_runtime" \
  monarch_configure_supergfxd Integrated; then
  fail "the supergfxd transaction accepted an unsupported Vfio value"
fi
[[ $(sha256sum "$publisher_config") == "$config_before" ]] ||
  fail "a failed supergfxd transaction changed the original configuration"
! find "${publisher_config%/*}" -maxdepth 1 -name '.supergfxd.conf.monarch.*' -print -quit | grep -q . ||
  fail "a failed supergfxd transaction left a staging file"
[[ ! -s $sudo_log ]] || fail "test-root configuration reached sudo"
pass "supergfxd configuration changes are validated before atomic publication"

system_root="$test_tmp/system-root"
runtime_root="$system_root/usr/share/monarch"
sleep_dir="$system_root/usr/lib/systemd/system-sleep"
drop_in_dir="$system_root/etc/systemd/system/supergfxd.service.d"
quarantine="$system_root/var/lib/monarch/reconcile/system-sleep-ownership"
mkdir -p "$sleep_dir" "$drop_in_dir" \
  "$runtime_root/default/systemd/system-sleep" \
  "$runtime_root/default/systemd/supergfxd.service.d"
cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" \
  "$ROOT/default/systemd/system-sleep/force-igpu" \
  "$runtime_root/default/systemd/system-sleep/"
cp "$ROOT/default/systemd/supergfxd.service.d/delay-start.conf" \
  "$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf"
chmod 0755 "$system_root" "$system_root/usr" "$system_root/usr/lib" \
  "$system_root/usr/lib/systemd" "$sleep_dir" "$system_root/etc" \
  "$system_root/etc/systemd" "$system_root/etc/systemd/system" "$drop_in_dir"
test_systemctl="$system_root/test-bin/systemctl"
systemctl_log="$test_tmp/systemctl.log"
mkdir -p "${test_systemctl%/*}"
cp "$fake_bin/systemctl" "$test_systemctl"
chmod 0755 "$test_systemctl"

if MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile" 2>/dev/null; then
  fail "reconciliation test mode accepted an implicit host systemctl"
fi
[[ ! -s $sudo_log ]] || fail "reconciliation test mode reached sudo"

cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$sleep_dir/keyboard-backlight"
chmod 0775 "$sleep_dir/keyboard-backlight"
admin_dir="$system_root/etc/monarch"
mkdir -p "$admin_dir"
printf '%s\n' '# administrator force-igpu hook' >"$admin_dir/force-igpu"
chmod 0755 "$admin_dir/force-igpu"
ln -s "$admin_dir/force-igpu" "$sleep_dir/force-igpu"
external_drop_in="$test_tmp/custom-delay.conf"
printf '%s\n' '[Service]' 'ExecStartPre=/bin/sleep 20' >"$external_drop_in"
ln -s "$external_drop_in" "$drop_in_dir/delay-start.conf"

MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"

cmp "$runtime_root/default/systemd/system-sleep/keyboard-backlight" \
  "$sleep_dir/keyboard-backlight" || fail "the unsafe keyboard hook was not repaired"
[[ $(stat -c '%a' "$sleep_dir/keyboard-backlight") == 755 ]] ||
  fail "the repaired keyboard hook is not executable"
[[ -L $sleep_dir/force-igpu && $(/usr/bin/realpath -e "$sleep_dir/force-igpu") == "$admin_dir/force-igpu" ]] ||
  fail "a trusted administrator hook was overwritten"
cmp "$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf" \
  "$drop_in_dir/delay-start.conf" || fail "the unsafe supergfxd drop-in was not repaired"
[[ $(<"$external_drop_in") == $'[Service]\nExecStartPre=/bin/sleep 20' ]] ||
  fail "the unsafe drop-in symlink target was modified"
find "$quarantine" -type l -lname "$external_drop_in" -print -quit | grep -q . ||
  fail "the unsafe custom drop-in was not preserved for administrator review"
[[ $(<"$systemctl_log") == 'daemon-reload' ]] ||
  fail "systemd was not reloaded after replacing its drop-in"
pass "V4 sleep files are repaired without overwriting trusted administrator changes"

MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ $(wc -l <"$systemctl_log") == 1 ]] ||
  fail "idempotent reconciliation reloaded systemd again"
pass "system-sleep ownership reconciliation is idempotent"

rm "$sleep_dir/force-igpu"
for fixture in force-igpu force-igpu-v4; do
  cp "$ROOT/test/fixtures/system-sleep-legacy/$fixture" "$sleep_dir/force-igpu"
  cp "$ROOT/test/fixtures/system-sleep-legacy/keyboard-backlight" "$sleep_dir/keyboard-backlight"
  chmod 0755 "$sleep_dir/force-igpu" "$sleep_dir/keyboard-backlight"
  MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
    SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
    PATH="$fake_bin:/usr/bin" bash "$reconcile"
  cmp "$runtime_root/default/systemd/system-sleep/force-igpu" "$sleep_dir/force-igpu" ||
    fail "the shipped $fixture hook did not receive the transition fix"
  cmp "$runtime_root/default/systemd/system-sleep/keyboard-backlight" "$sleep_dir/keyboard-backlight" ||
    fail "the shipped keyboard hook did not receive the composite-sleep fix"
done
printf '%s\n' '# administrator regular hook' >"$sleep_dir/force-igpu"
MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ $(<"$sleep_dir/force-igpu") == '# administrator regular hook' ]] ||
  fail "a customized regular hook was mistaken for a shipped version"
pass "recognized root-owned hooks are refreshed while custom regular hooks are preserved"

chmod 0664 "$drop_in_dir/delay-start.conf"
if MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" SYSTEMCTL_FAIL=1 \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"; then
  fail "a failed systemd reload reported a completed repair"
fi
[[ -e $quarantine/systemd-reload-needed ]] ||
  fail "a failed systemd reload did not leave a retry marker"

MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ ! -e $quarantine/systemd-reload-needed ]] ||
  fail "a successful retry did not clear the systemd reload marker"
[[ $(wc -l <"$systemctl_log") == 3 ]] ||
  fail "the pending systemd reload was not retried exactly once"
pass "a failed systemd reload remains retryable"

chmod 0777 "$system_root/var/lib/monarch"
chmod 0664 "$drop_in_dir/delay-start.conf"
if MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"; then
  fail "reconciliation accepted a writable state ancestor"
fi
[[ $(stat -c '%a' "$drop_in_dir/delay-start.conf") == 664 ]] ||
  fail "reconciliation mutated a file after rejecting its state directory"
chmod 0700 "$system_root/var/lib/monarch"
MONARCH_SLEEP_TEST_ROOT="$system_root" MONARCH_SLEEP_TEST_SYSTEMCTL="$test_systemctl" MONARCH_PATH="$runtime_root" \
  SUDO_LOG="$sudo_log" SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$fake_bin:/usr/bin" bash "$reconcile"
[[ $(wc -l <"$systemctl_log") == 4 ]] ||
  fail "reconciliation did not recover after the state boundary was repaired"
pass "reconciliation rejects unsafe state ancestors before publication"

hibernation="$ROOT/bin/monarch-hibernation-setup"
hybrid="$ROOT/bin/monarch-toggle-hybrid-gpu"
! grep -Eq 'cp -p .*system-sleep|cp -p .*supergfxd' "$hibernation" "$hybrid" ||
  fail "a privileged sleep file still inherits user ownership"
grep -qF 'source /usr/share/monarch/install/helpers/root-file.sh' "$hibernation" ||
  fail "hibernation loads its privileged publisher from an untrusted runtime"
grep -qF 'source /usr/share/monarch/install/helpers/root-file.sh' "$hybrid" ||
  fail "hybrid GPU setup loads its privileged publisher from an untrusted runtime"
! grep -Eq 'monarch_install_root_file.*MONARCH_PATH' "$hibernation" "$hybrid" ||
  fail "a privileged sleep payload still comes from MONARCH_PATH"
! grep -Eq 'rm -rf .*(force-igpu|delay-start\.conf)' "$hybrid" ||
  fail "hybrid GPU cleanup bypasses the trusted root-file remover"

hook_line=$(grep -En 'monarch_install_root_file keyboard-backlight' "$hibernation" | cut -d: -f1)
resume_line=$(grep -En 'echo "HOOKS\+=\(resume\)"' "$hibernation" | cut -d: -f1)
[[ -n $hook_line && -n $resume_line && $hook_line -lt $resume_line ]] ||
  fail "hibernation becomes complete before its sleep hook is safely published"

force_line=$(grep -En 'monarch_install_root_file force-igpu' "$hybrid" | cut -d: -f1)
delay_line=$(grep -En 'monarch_install_root_file delay-start' "$hybrid" | cut -d: -f1)
mode_line=$(grep -nF 'monarch_configure_supergfxd Integrated' "$hybrid" | cut -d: -f1)
reboot_line=$(grep -nF 'monarch-system-reboot' "$hybrid" | tail -1 | cut -d: -f1)
[[ -n $force_line && -n $delay_line && -n $mode_line ]] ||
  fail "hybrid GPU setup is missing a safely published support file"
((force_line < mode_line && delay_line < mode_line && mode_line < reboot_line)) ||
  fail "hybrid GPU mode changes before its support files are safely published"
preflight_line=$(grep -nF 'monarch_root_file_can_remove force-igpu' "$hybrid" | cut -d: -f1)
hybrid_mode_line=$(grep -nF 'monarch_configure_supergfxd Hybrid' "$hybrid" | cut -d: -f1)
[[ -n $preflight_line && -n $hybrid_mode_line && $preflight_line -lt $hybrid_mode_line ]] ||
  fail "dedicated GPU mode changes before customized support files are detected"
grep -qF 'Could not configure supergfxd for integrated mode' "$hybrid" ||
  fail "hybrid GPU setup does not stop after a failed configuration rewrite"
grep -qF 'Could not configure supergfxd for hybrid mode' "$hybrid" ||
  fail "dedicated GPU setup does not stop after a failed configuration rewrite"
pass "sleep support files are published before their configurations become active"

hook_copy="$test_tmp/force-igpu"
cp "$ROOT/default/systemd/system-sleep/force-igpu" "$hook_copy"
chmod 0755 "$hook_copy"
"$hook_copy" ignored suspend || fail "the force-igpu hook is not directly executable"
[[ $(head -1 "$hook_copy") == '#!/bin/bash' ]] || fail "the force-igpu shebang is not first"
pass "the installed force-igpu hook has a valid executable format"

grep -qF 'sudo bash /usr/share/monarch/install/reconcile/system-sleep-ownership.sh' \
  "$ROOT/install/reconcile/system.sh" ||
  fail "current-schema reconciliation does not repair historical sleep files"
! grep -qF 'system-sleep-ownership.sh' "$ROOT/install/reconcile/schema/1-to-2/system.sh" ||
  fail "sleep ownership remains limited to the V4 system transition"
pass "every supported schema runs the ownership repair"
