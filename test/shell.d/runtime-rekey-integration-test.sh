#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
export ROOT test_tmp
python3 - <<'PY'
import os
from pathlib import Path
root, temp = Path(os.environ['ROOT']), Path(os.environ['test_tmp'])
for source, name in [('bin/monarch-system-factory-reset', 'reset'), ('install/provisioning/luks-rekey.sh', 'provision'), ('install/drive-password/rekey.sh', 'manual')]:
    text = (root / source).read_text()
    text = text.replace('/run/monarch-drive-password.lock', str(temp / 'drive.lock'))
    text = text.replace('/run/monarch-system-factory-reset.lock', str(temp / 'reset.lock'))
    text = text.replace('/var/lib/monarch-drive-password', str(temp / 'manual-state'))
    text = text.replace('/var/lib/monarch/provisioning', str(temp / 'live-provisioning'))
    if name == 'manual':
        text = text.split('if [[ ! -e $state_dir')[0]
        text = text.replace('&& $EUID == 0', '&& $EUID == ' + str(os.getuid()))
        text = text.replace('&& -b $1', '&& $1 == /dev/fixture').replace('&& -b $drive', '&& $drive == /dev/fixture')
        text += 'exit 42\n'
    (temp / name).write_text(text)
PY
MONARCH_FACTORY_RESET_LIB_ONLY=true source "$test_tmp/reset"
LOG_FILE="$test_tmp/reset.log"
gum() { :; }
log() { :; }
fail_test() { echo "FAIL: $*" >&2; exit 1; }
eval "$(declare -f stage_current_owner_provisioning | sed '1s/stage_current_owner_provisioning/current_owner/')"
stage_current_owner_provisioning() { current_owner "$1" "$ROOT"; }

for encrypted in true false; do
  (
    TOP_MNT="$test_tmp/reset-$encrypted"
    factory="$TOP_MNT/@factory"
    next="$TOP_MNT/$NEXT_NAME"
    mkdir -p "$TOP_MNT/@" "$factory$PROVISIONING_DIR" "$PROVISIONING_DIR" \
      "$factory/usr/share/monarch/"{bin,install/provisioning} "$factory/usr/bin" "$factory/etc"
    printf 'live-journal\n' >"$PROVISIONING_DIR/luks-rekey-state"
    printf 'live-temporary\n' >"$PROVISIONING_DIR/.luks-rekey.live"
    printf 'old-journal\n' >"$factory$PROVISIONING_DIR/luks-rekey-state"
    printf 'old-temporary\n' >"$factory$PROVISIONING_DIR/.luks-rekey.stale"
    printf 'retain\n' >"$factory$PROVISIONING_DIR/local-recovery"
    cp "$ROOT/install/provisioning/"*.service "$factory/usr/share/monarch/install/provisioning/"
    printf '#!/bin/bash\nexit 0\n' >"$factory/usr/bin/monarch-provision-owner"
    chmod 755 "$factory/usr/bin/monarch-provision-owner"
    btrfs() { [[ $1 == subvolume && $2 == snapshot && $3 == "$factory" && $4 == "$next" ]] || exit 91; cp -a "$3" "$4"; }
    retire_factory_privilege_grants() { :; }
    retire_factory_printer_discovery() { :; }
    stage_current_apple_display_access() { :; }
    scrub_factory_accounts() { :; }
    sanitize_factory_baseline() { :; }
    systemd-id128() { printf '%032d\n' 1; }
    encrypted_install() { "$encrypted"; }
    clean_journal() {
      [[ ! -e $next$PROVISIONING_DIR/luks-rekey-state ]] || exit 92
      ! compgen -G "$next$PROVISIONING_DIR/.luks-rekey.*" >/dev/null || exit 93
      [[ $(<"$next$PROVISIONING_DIR/local-recovery") == retain ]] || exit 94
      [[ $(<"$PROVISIONING_DIR/luks-rekey-state") == live-journal ]] || exit 95
      [[ $(<"$PROVISIONING_DIR/.luks-rekey.live") == live-temporary ]] || exit 96
    }
    stage_luks_rekey() { clean_journal; touch "$test_tmp/key-$encrypted"; }
    rebuild_next_boot() {
      clean_journal
      cmp "$ROOT/install/provisioning/luks-rekey.sh" "$next/usr/share/monarch/install/provisioning/luks-rekey.sh"
      [[ -f $next/etc/systemd/system/monarch-provision-owner.service ]]
    }
    activate_factory_root() { :; }
    commit_esp_staging() { :; }
    umount() { :; }
    sync() { :; }
    stage_full_reset
    clean_journal
    [[ ! -e $factory$PROVISIONING_DIR/.luks-rekey.live ]]
    [[ $(<"$factory$PROVISIONING_DIR/luks-rekey-state") == old-journal ]]
    if $encrypted; then [[ -e $test_tmp/key-$encrypted ]]; else [[ ! -e $test_tmp/key-$encrypted ]]; fi
  )
done
echo 'PASS: encrypted/unencrypted reset clears only cloned journals before a new key; live/factory records and local recovery survive'

redirected="$test_tmp/redirected-clone"
mkdir -p "$redirected${PROVISIONING_DIR%/*}"
ln -s "$PROVISIONING_DIR" "$redirected$PROVISIONING_DIR"
if (prepare_reset_provisioning "$redirected") >"$test_tmp/redirected.log" 2>&1; then fail_test 'cloned state symlink accepted'; fi
[[ $(<"$PROVISIONING_DIR/luks-rekey-state") == live-journal ]]
[[ $(<"$PROVISIONING_DIR/.luks-rekey.live") == live-temporary ]]
rm "$redirected$PROVISIONING_DIR"
rm -rf "$redirected${PROVISIONING_DIR%/*}"
ln -s "${PROVISIONING_DIR%/*}" "$redirected${PROVISIONING_DIR%/*}"
if (prepare_reset_provisioning "$redirected") >"$test_tmp/redirected-parent.log" 2>&1; then fail_test 'cloned ancestor symlink accepted'; fi
[[ $(<"$PROVISIONING_DIR/luks-rekey-state") == live-journal ]]
echo 'PASS: cloned state and ancestor symlinks cannot redirect journal cleanup into live provisioning'

hib_root="$test_tmp/old-factory"
mkdir -p "$hib_root/usr/share/monarch/bin"
stage_current_hibernation "$hib_root" "$ROOT"
for relative in bin/monarch-hibernation-setup install/helpers/as-root.sh install/helpers/root-file.sh \
  install/helpers/hibernation-lock.sh install/reconcile/hibernation-resume.sh default/systemd/system-sleep/keyboard-backlight; do
  cmp "$ROOT/$relative" "$hib_root/usr/share/monarch/$relative"
done
[[ $(stat -c %a "$hib_root/usr/share/monarch/install/helpers/hibernation-lock.sh") == 644 ]]
[[ -x $hib_root/usr/share/monarch/bin/monarch-hibernation-setup ]]
mkdir "$test_tmp/bad-runtime"
ln -s "$test_tmp/bad-runtime" "$hib_root/usr/share/monarch/install/reconcile/bad-link"
rm "$hib_root/usr/share/monarch/install/reconcile/hibernation-resume.sh"
ln -s "$test_tmp/missing-payload" "$hib_root/usr/share/monarch/install/reconcile/hibernation-resume.sh"
stage_current_hibernation "$hib_root" "$ROOT"
[[ ! -L $hib_root/usr/share/monarch/install/reconcile/hibernation-resume.sh ]]
rm -rf "$hib_root/usr/share/monarch/install/helpers"
ln -s "$test_tmp/bad-runtime" "$hib_root/usr/share/monarch/install/helpers"
if (stage_current_hibernation "$hib_root" "$ROOT") >"$test_tmp/hib-unsafe.log" 2>&1; then fail_test 'unsafe factory parent accepted'; fi
[[ ! -e $test_tmp/bad-runtime/root-file.sh ]]
echo 'PASS: old factory receives complete current hibernation dependencies; symlink parents cannot redirect root copies'

mkdir -p "$test_tmp/manual-state"
rm -f "$PROVISIONING_DIR/luks-rekey-state" "$PROVISIONING_DIR/.luks-rekey.live"
fixture_uuid=01234567-89ab-cdef-0123-456789abcdef
luks_device() { echo /dev/fixture; }
cryptsetup() { [[ $1 == luksUUID ]] || exit 97; echo "$fixture_uuid"; }
timeout() { [[ $1 == --kill-after=5s && $2 == 120s ]] || return 96; shift 2; "$@"; }
reset_disk_transition_ready
touch "$test_tmp/manual-state/$fixture_uuid.json"
if (reset_disk_transition_ready); then fail_test 'reset accepted a pending manual journal'; fi
rm "$test_tmp/manual-state/$fixture_uuid.json"
for marker in pending wipe-pending luks-key; do
  touch "$PROVISIONING_DIR/$marker"
  if (reset_disk_transition_ready); then fail_test "reset accepted provisioning $marker"; fi
  code=0
  /usr/bin/bash -p "$test_tmp/manual" /dev/fixture >"$test_tmp/manual.log" 2>&1 || code=$?
  [[ $code == 1 ]] || fail_test "manual accepted provisioning $marker"
  rm "$PROVISIONING_DIR/$marker"
done
printf 'phase=owner\n' >"$PROVISIONING_DIR/luks-rekey-state"
if (reset_disk_transition_ready); then fail_test 'reset accepted incomplete provisioning'; fi
code=0
/usr/bin/bash -p "$test_tmp/manual" /dev/fixture >"$test_tmp/manual.log" 2>&1 || code=$?
[[ $code == 1 ]] || fail_test 'manual accepted incomplete provisioning'
printf 'phase=done\n' >"$PROVISIONING_DIR/luks-rekey-state"
reset_disk_transition_ready
code=0
/usr/bin/bash -p "$test_tmp/manual" /dev/fixture >"$test_tmp/manual.log" 2>&1 || code=$?
[[ $code == 42 ]] || fail_test 'completed provisioning prevents later manual recovery keys'

source "$test_tmp/provision"
rekey_private_path() { [[ ! -L $1 ]]; }
touch "$test_tmp/manual-state/$fixture_uuid.json"
if (luks_rekey /dev/fixture); then fail_test 'provisioning accepted a manual journal'; fi
rm "$test_tmp/manual-state/$fixture_uuid.json"
exec {held}>"$test_tmp/drive.lock"
flock -n "$held"
if (luks_rekey /dev/fixture); then fail_test 'provisioning ignored the shared lock'; fi
if (main); then fail_test 'reset ignored the shared lock'; fi
code=0
/usr/bin/bash -p "$test_tmp/manual" /dev/fixture >"$test_tmp/manual.log" 2>&1 || code=$?
[[ $code == 1 ]] || fail_test 'manual ignored the shared lock'
grep -q 'Another drive password change' "$test_tmp/manual.log"
flock -u "$held"
exec {held}>&-
echo 'PASS: all three flows share real flock exclusion, reject incompatible journals and allow completed provisioning'

python3 - <<'PY'
import os
from pathlib import Path
root, temp = Path(os.environ['ROOT']), Path(os.environ['test_tmp'])
unit = (root / 'install/provisioning/monarch-provision-owner.service').read_text()
assert 'ExecStart=/usr/bin/monarch-provision-owner\n' in unit
text = (root / 'bin/monarch-provision-owner').read_text().split('LOGO_PATH=')[0]
text = text.replace('EUID != 0', 'EUID != ' + str(os.getuid()))
text = text.replace('PROVISIONING_DIR=/var/lib/monarch/provisioning', 'PROVISIONING_DIR=' + str(temp / 'service-state'))
text = text.replace('MONARCH_PATH=/usr/share/monarch', 'MONARCH_PATH=' + str(root))
text += 'declare -F luks_rekey >/dev/null\n'
(temp / 'service-owner').write_text(text)
(temp / 'service-owner').chmod(0o755)
(temp / 'service-state').mkdir()
(temp / 'service-state/pending').touch()
PY
printf 'touch "%s/injected"\n' "$test_tmp" >"$test_tmp/bash-env"
BASH_ENV="$test_tmp/bash-env" "$test_tmp/service-owner"
[[ ! -e $test_tmp/injected ]]
if bash "$test_tmp/service-owner" -p >"$test_tmp/ordinary.log" 2>&1; then fail_test 'ordinary Bash accepted'; fi
echo 'PASS: direct service-style owner launch preserves Bash -p and loads the shipped form/rekey helper without startup injection'
