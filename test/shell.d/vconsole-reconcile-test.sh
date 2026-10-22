#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

system_root="$test_tmp/system"
stub_bin="$test_tmp/bin"
config_dir="$system_root/etc/mkinitcpio.conf.d"
vconsole="$system_root/etc/vconsole.conf"
state_dir="$system_root/var/lib/monarch"
marker="$state_dir/vconsole-initramfs.sha256"
calls="$test_tmp/calls"
mkdir -p "$config_dir" "$stub_bin" "$system_root/usr/lib/initcpio/install" \
  "$system_root/usr/share/monarch" "$system_root/var/lib"
for command in bash cat chmod dirname find grep install ln mktemp mv rm sha256sum sort tee; do
  ln -s "$(command -v "$command")" "$stub_bin/$command"
done
for config in "$ROOT/etc/mkinitcpio.conf.d/monarch"*.conf; do
  sed "s|/etc/vconsole.conf|$vconsole|g" "$config" >"$config_dir/${config##*/}"
done
printf '%s\n' 'FILES=()' 'HOOKS=(base plymouth encrypt)' >"$system_root/etc/mkinitcpio.conf"
printf '%s\n' 'add_file /etc/vconsole.conf' >"$system_root/usr/lib/initcpio/install/plymouth"
printf '%s\n' 'XKBLAYOUT=ru' >"$vconsole"
cat >"$stub_bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
printf 'limine-mkinitcpio%s\n' "${*:+ $*}" >>"$TEST_CALLS"
[[ ${TEST_REBUILD_MESSAGE:-} == "" ]] || echo "$TEST_REBUILD_MESSAGE"
exit "${TEST_REBUILD_STATUS:-0}"
EOF
cat >"$stub_bin/mkinitcpio" <<'EOF'
#!/bin/bash
printf 'mkinitcpio %s\n' "$*" >>"$TEST_CALLS"
exit "${TEST_REBUILD_STATUS:-0}"
EOF
chmod +x "$stub_bin/limine-mkinitcpio" "$stub_bin/mkinitcpio"

export MONARCH_ROOT_FILE_TEST_ROOT="$system_root"
export MONARCH_ROOT_FILE_TEST_RUNTIME="$system_root/usr/share/monarch"
export TEST_CALLS="$calls"
export PATH="$stub_bin"

reconcile() {
  bash "$ROOT/install/reconcile/vconsole-initramfs.sh" </dev/null
}

TEST_REBUILD_STATUS=42
export TEST_REBUILD_STATUS
if reconcile; then
  fail "a failed boot image rebuild completed reconciliation"
else
  [[ $? == 42 ]] || fail "the boot image rebuild status was lost"
fi
[[ ! -e $marker ]] || fail "a failed boot image rebuild was marked complete"
[[ $(<"$calls") == "limine-mkinitcpio" ]] || fail "Limine did not own the rebuild"
pass "failed rebuilds remain pending and do not fall back to classic images"

TEST_REBUILD_STATUS=0
TEST_REBUILD_MESSAGE='ERROR: mkinitcpio failed for kernel linux-cachyos'
export TEST_REBUILD_MESSAGE
if reconcile; then
  fail "a per-kernel rebuild failure reported with status zero was accepted"
fi
[[ ! -e $marker ]] || fail "an incomplete kernel rebuild was marked complete"
unset TEST_REBUILD_MESSAGE
pass "per-kernel failures cannot masquerade as a successful Limine rebuild"

: >"$calls"
reconcile
[[ -f $marker && $(<"$calls") == "limine-mkinitcpio" ]] ||
  fail "a successful retry did not complete the rebuild"
[[ $(/usr/bin/stat -c %a "$marker") == "644" ]] || fail "the rebuild marker has unexpected permissions"
: >"$calls"
reconcile
[[ ! -s $calls ]] || fail "an unchanged guard rebuilt the boot images again"
pass "a successful rebuild is machine-wide and idempotent"

preset_dir="$system_root/etc/mkinitcpio.d"
install -d "$preset_dir"
for setting in 'ALL_config="/etc/mkinitcpio.conf"' 'fallback_config="/etc/custom-initramfs.conf"'; do
  printf '%s\n' 'PRESETS=(default fallback)' "$setting" >"$preset_dir/linux.preset"
  before=$(sha256sum "$preset_dir/linux.preset" "$marker")
  if reconcile >"$test_tmp/preset-error" 2>&1; then
    fail "an explicit preset configuration was hidden by the successful rebuild marker"
  fi
  grep -qF 'linux.preset' "$test_tmp/preset-error" || fail "the diagnostic omitted the affected preset file"
  grep -qF 'config' "$test_tmp/preset-error" || fail "the diagnostic omitted the configuration override"
  [[ ! -s $calls && $(sha256sum "$preset_dir/linux.preset" "$marker") == "$before" ]] ||
    fail "an unsupported preset changed configuration, rebuilt images or updated success state"
done
rm "$marker"
if reconcile >"$test_tmp/preset-error" 2>&1; then
  fail "a fresh repair accepted a preset that bypasses the keyboard guard"
fi
[[ ! -s $calls && ! -e $marker ]] || fail "an unsupported preset was marked repaired"
pass "global and per-image preset configurations fail before rebuilding, even with an old success marker"

printf '%s\n' 'PRESETS=(default)' 'fallback_config="/etc/unused.conf"' >"$preset_dir/linux.preset"
printf '%s\n' 'PRESETS=(default fallback)' >"$preset_dir/other.preset"
reconcile
[[ $(<"$calls") == 'limine-mkinitcpio' && -f $marker ]] ||
  fail "default presets or an inactive override blocked the repair"
: >"$calls"
reconcile
[[ ! -s $calls ]] || fail "default presets broke idempotence"
printf '%s\n' 'PRESETS=(default)' 'ALL_config=' >"$preset_dir/linux.preset"
reconcile
[[ ! -s $calls ]] || fail "an empty preset configuration blocked the default path"
printf '%s\n' 'return 7' >"$preset_dir/linux.preset"
if reconcile >/dev/null 2>&1; then
  fail "an unreadable preset evaluation was accepted"
fi
[[ ! -s $calls ]] || fail "an invalid preset started reconstruction"
rm "$preset_dir/linux.preset" "$preset_dir/other.preset"
pass "preset evaluation is isolated, respects active image names and recovers after configuration repair"

printf '\n' >>"$config_dir/monarch_vconsole.conf"
reconcile
[[ $(<"$calls") == "limine-mkinitcpio" ]] || fail "an updated guard did not rebuild stale images"
pass "changing the packaged guard invalidates the successful rebuild marker"

rm "$marker"
: >"$calls"
printf '%s\n' 'XKBLAYOUT=de' >"$vconsole"
reconcile
[[ ! -s $calls && ! -e $marker ]] || fail "a Latin primary layout caused an unnecessary rebuild"
printf '%s\n' 'XKBLAYOUT=ru' >"$vconsole"
printf 'FILES+=("%s")\n' "$vconsole" >"$config_dir/zz-admin.conf"
reconcile
[[ ! -s $calls && ! -e $marker ]] || fail "an explicit administrator FILES entry was ignored"
rm "$config_dir/zz-admin.conf"
pass "Latin layouts and explicit administrator configuration are preserved"

printf 'FILES+=("%s")\n' "$vconsole" >"$config_dir/zz-2-admin.conf"
printf '%s\n' 'FILES=()' >"$config_dir/zz-10-admin.conf"
reconcile
[[ $(<"$calls") == 'limine-mkinitcpio' && -f $marker ]] ||
  fail "configuration evaluation did not use mkinitcpio version ordering"
rm "$marker"
: >"$calls"
printf '%s\n' 'FILES=()' >"$config_dir/zz-2-admin.conf"
printf 'FILES+=("%s")\n' "$vconsole" >"$config_dir/zz-10-admin.conf"
reconcile
[[ ! -s $calls && ! -e $marker ]] || fail "a version-ordered FILES opt-in was ignored"
rm "$config_dir/zz-2-admin.conf" "$config_dir/zz-10-admin.conf"
pass "configuration evaluation matches mkinitcpio version ordering"

printf '%s\n' 'HOOKS=(base encrypt)' >"$config_dir/zz-admin.conf"
reconcile
[[ ! -s $calls && ! -e $marker ]] || fail "disabled Plymouth caused a boot image rebuild"
rm "$config_dir/zz-admin.conf"
mv "$vconsole" "$vconsole.saved"
reconcile
mv "$vconsole.saved" "$vconsole"
[[ ! -s $calls && ! -e $marker ]] || fail "a missing keyboard configuration caused a rebuild"
printf '%s\n' 'build() { :; }' >"$system_root/usr/lib/initcpio/install/plymouth"
reconcile
[[ ! -s $calls && ! -e $marker ]] || fail "an unaffected Plymouth hook caused a rebuild"
printf '%s\n' 'add_file /etc/vconsole.conf' >"$system_root/usr/lib/initcpio/install/plymouth"
pass "unaffected configurations do not rebuild their boot images"

printf '%s\n' 'return 7' >"$config_dir/zz-admin.conf"
if reconcile >/dev/null 2>&1; then
  fail "an invalid mkinitcpio configuration was silently accepted"
fi
[[ ! -s $calls && ! -e $marker ]] || fail "an invalid configuration rebuilt or completed"
rm "$config_dir/zz-admin.conf"
pass "configuration evaluation fails closed before rebuilding"

rm "$stub_bin/limine-mkinitcpio"
reconcile
[[ $(<"$calls") == 'mkinitcpio -P' && -f $marker ]] ||
  fail "a machine without Limine did not rebuild classic images"
pass "classic mkinitcpio is used only when Limine is unavailable"

chmod 0666 "$marker"
: >"$calls"
if reconcile >/dev/null 2>&1; then
  fail "a writable rebuild marker was trusted"
fi
[[ ! -s $calls ]] || fail "an unsafe rebuild marker did not stop reconstruction"
chmod 0644 "$marker"
chmod 0777 "$state_dir"
if reconcile >/dev/null 2>&1; then
  fail "a writable rebuild state directory was trusted"
fi
chmod 0755 "$state_dir"
pass "rebuild state rejects writable files and directories"

rm "$marker"
ln -s "$test_tmp/unrelated" "$marker"
: >"$calls"
if reconcile >/dev/null 2>&1; then
  fail "a symlinked rebuild marker was accepted"
fi
[[ ! -s $calls && ! -e $test_tmp/unrelated ]] || fail "a symlinked marker was followed"
pass "rebuild state cannot follow a symlink"

/usr/bin/grep -qF 'sudo bash /usr/share/monarch/install/reconcile/vconsole-initramfs.sh' \
  "$ROOT/install/reconcile/system.sh" || fail "current-schema reconciliation does not repair stale boot images"
pass "all supported schemas reconcile the keyboard fix"
