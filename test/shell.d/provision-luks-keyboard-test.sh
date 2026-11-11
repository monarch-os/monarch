#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
system_root="$test_tmp/system"
mkdir -p "$system_root/etc/mkinitcpio.conf.d" "$system_root/usr/lib/initcpio/hooks" \
  "$system_root/usr/bin" "$system_root/usr/share/X11/xkb/symbols" \
  "$system_root/usr/share/X11/locale/en_US.UTF-8"
python3 - "$ROOT" "$system_root" "$test_tmp" <<'PY'
from pathlib import Path
import sys
repo, system, temp = map(Path, sys.argv[1:])
text = (repo / 'install/provisioning/luks-rekey.sh').read_text()
text = text.replace('/run/monarch-drive-password.lock', str(temp / 'drive.lock'))
text = text.replace('/var/lib/monarch-drive-password/', str(temp / 'manual') + '/')
text = text.replace('/etc/', str(system / 'etc') + '/')
text = text.replace('rekey_private_path /etc ', 'rekey_private_path ' + str(system / 'etc') + ' ')
text = text.replace('system = Path("/")', 'system = Path(' + repr(str(system)) + ')')
(temp / 'helper.sh').write_text(text)
for source in (repo / 'etc/mkinitcpio.conf.d').glob('monarch*.conf'):
    (system / 'etc/mkinitcpio.conf.d' / source.name).write_text(source.read_text().replace('/etc/vconsole.conf', str(system / 'etc/vconsole.conf')))
PY
source "$test_tmp/helper.sh"
rekey_private_path() { [[ ! -L $1 ]]; }
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'HOOKS=(base plymouth keymap encrypt)\nFILES=()\n' >"$system_root/etc/mkinitcpio.conf"
printf 'LANG=en_US.UTF-8\n' >"$system_root/etc/locale.conf"
for file in init init_functions; do printf 'fixture-%s\n' "$file" >"$system_root/usr/lib/initcpio/$file"; done
for file in keymap plymouth encrypt; do
  printf 'fixture-%s-hook\n' "$file" >"$system_root/usr/lib/initcpio/hooks/$file"
done
for file in plymouth plymouthd; do printf 'fixture-%s\n' "$file" >"$system_root/usr/bin/$file"; chmod 755 "$system_root/usr/bin/$file"; done
printf 'fixture-plymouth-26-input-implementation' >"$system_root/usr/lib/libply-splash-core.so.5.0"
ln -s libply-splash-core.so.5.0 "$system_root/usr/lib/libply-splash-core.so.5"
printf 'fixture-xkb-default-us' >"$system_root/usr/lib/libxkbcommon.so.0.1"
ln -s libxkbcommon.so.0.1 "$system_root/usr/lib/libxkbcommon.so.0"
printf 'fixture-XKB-us' >"$system_root/usr/share/X11/xkb/symbols/us"
printf 'fixture-XKB-fr' >"$system_root/usr/share/X11/xkb/symbols/fr"
printf 'fixture-XKB-ru' >"$system_root/usr/share/X11/xkb/symbols/ru"
printf 'en_US.UTF-8/Compose C\n' >"$system_root/usr/share/X11/locale/compose.dir"
printf '<dead_acute> <e> : "é"\n' >"$system_root/usr/share/X11/locale/en_US.UTF-8/Compose"
printf 'fixture-console-includes-v1' >"$test_tmp/console-include"
loadkeys() {
  [[ $1 == -q && ${*: -1} == -b ]] || return 90
  printf 'fixture-binary-map:%s:' "$*"
  cat "$test_tmp/console-include"
}
make_case() {
  case_dir="$test_tmp/$1"
  mkdir -p "$case_dir/expected" "$case_dir/image/etc" "$case_dir/image/hooks"
  printf 'KEYMAP=%s\nXKBLAYOUT="%s"\nXKBOPTIONS="compose:ralt"\n' "$2" "$3" >"$system_root/etc/vconsole.conf"
  rekey_keyboard_prepare "$case_dir/expected" >"$case_dir/prepare.log" 2>&1 || { cat "$case_dir/prepare.log" >&2; fail "prepare $1"; }
  cp -a "$system_root/usr" "$case_dir/image/"
  cp "$system_root/usr/lib/initcpio/init" "$case_dir/image/init"
  cp "$system_root/usr/lib/initcpio/init_functions" "$case_dir/image/init_functions"
  cp -a "$system_root/usr/lib/initcpio/hooks/." "$case_dir/image/hooks/"
  chmod 755 "$case_dir/image/init" "$case_dir/image/hooks/"*
  cp "$case_dir/expected/keymap.bin" "$case_dir/image/keymap.bin"
  if [[ -f $case_dir/expected/keymap.utf8 ]]; then cp "$case_dir/expected/keymap.utf8" "$case_dir/image/keymap.utf8"; fi
  if [[ -f $case_dir/expected/vconsole.conf ]]; then cp "$case_dir/expected/vconsole.conf" "$case_dir/image/etc/vconsole.conf"; fi
  printf 'MODULES=""\nEARLYHOOKS="udev"\nHOOKS="plymouth keymap encrypt"\nLATEHOOKS="plymouth"\nCLEANUPHOOKS=""\nEMERGENCYHOOKS="plymouth"\n' >"$case_dir/image/config"
}
verify() { rekey_verify_keyboard "$case_dir/image" "$case_dir/expected" >"$case_dir/verify.log" 2>&1; }
for description in 'latin:fr:fr' 'latin-first:fr:fr,ru' 'nonlatin:ru:ru' 'nonlatin-first:gr:gr,us' 'keymap-only:de-latin1:'; do
  IFS=: read -r name keymap xkb <<<"$description"
  make_case "$name" "$keymap" "$xkb"
  verify || { cat "$case_dir/verify.log" >&2; fail "$name"; }
  case $name in
    nonlatin*) [[ ! -e $case_dir/image/etc/vconsole.conf ]] || fail 'non-Latin implicit copy' ;;
    *) [[ -f $case_dir/image/etc/vconsole.conf ]] || fail 'Latin config missing' ;;
  esac
done
echo 'PASS: Latin, mixed primary layouts, non-Latin Plymouth fallback and KEYMAP-only boot contracts'
mv "$system_root/usr/share/X11/xkb" "$system_root/usr/share/xkeyboard-config-2"
ln -s ../xkeyboard-config-2 "$system_root/usr/share/X11/xkb"
make_case symlinked-xkb fr fr
verify || { cat "$case_dir/verify.log" >&2; fail 'symlinked xkb tree rejected'; }
rm "$system_root/usr/share/X11/xkb"
mv "$system_root/usr/share/xkeyboard-config-2" "$system_root/usr/share/X11/xkb"
echo 'PASS: a packaged xkb tree reached through a validated symlink is accepted'
printf 'LANG=C\n' >"$system_root/etc/locale.conf"
make_case console-nonunicode us us
verify || fail 'non-Unicode console'
[[ ! -e $case_dir/image/keymap.utf8 ]] || fail 'C locale selected Unicode mode'
printf 'LANG=en_US.UTF-8\n' >"$system_root/etc/locale.conf"
keyboard=fr
mkdir "$case_dir/mismatched-selection"
if rekey_keyboard_prepare "$case_dir/mismatched-selection" >"$case_dir/prepare.log" 2>&1; then fail 'persisted map differs from form selection'; fi
unset keyboard
echo 'PASS: console Unicode mode follows locale and the persisted map must match the provisioning selection'

make_case explicit-nonlatin ru ru
printf 'FILES+=(%q)\n' "$system_root/etc/vconsole.conf" >"$system_root/etc/mkinitcpio.conf.d/zz-admin.conf"
rm -rf "$case_dir/expected"
mkdir "$case_dir/expected"
rekey_keyboard_prepare "$case_dir/expected"
cp "$case_dir/expected/vconsole.conf" "$case_dir/image/etc/vconsole.conf"
verify || fail 'explicit administrator FILES override'
rm "$system_root/etc/mkinitcpio.conf.d/zz-admin.conf"
echo 'PASS: explicit vconsole inclusion remains supported and is verified rather than silently omitted'

make_case digest ru ru
original=$(<"$case_dir/expected/fingerprint")
printf 'fixture-console-includes-v2' >"$test_tmp/console-include"
mkdir "$case_dir/changed"
rekey_keyboard_prepare "$case_dir/changed"
[[ $(<"$case_dir/changed/fingerprint") != "$original" ]] || fail 'console includes not fingerprinted'
if rekey_verify_keyboard "$case_dir/image" "$case_dir/changed" >"$case_dir/verify.log" 2>&1; then fail 'stale compiled map accepted'; fi
echo 'PASS: changes to included console maps invalidate the journal fingerprint and old image'
mkdir "$case_dir/compose-changed"
printf '# changed compose table\n' >>"$system_root/usr/share/X11/locale/en_US.UTF-8/Compose"
rekey_keyboard_prepare "$case_dir/compose-changed"
[[ $(<"$case_dir/compose-changed/fingerprint") != "$(<"$case_dir/changed/fingerprint")" ]] || fail 'compose not fingerprinted'
if rekey_verify_keyboard "$case_dir/image" "$case_dir/compose-changed" >"$case_dir/verify.log" 2>&1; then fail 'stale compose data accepted'; fi
echo 'PASS: compose data participates in the retry fingerprint'

for fault in console-map unicode unicode-directory missing-latin unexpected-nonlatin compose xkb-data xkb-extra xkb-library hook-payload hook-order init-payload config-env override symlink-map fifo-map; do
  case $fault in missing-latin) make_case "bad-$fault" fr fr ;; *) make_case "bad-$fault" ru ru ;; esac
  case $fault in
    console-map) printf wrong >"$case_dir/image/keymap.bin" ;;
    unicode) rm "$case_dir/image/keymap.utf8" ;;
    unicode-directory) rm "$case_dir/image/keymap.utf8"; mkdir "$case_dir/image/keymap.utf8" ;;
    missing-latin) rm "$case_dir/image/etc/vconsole.conf" ;;
    unexpected-nonlatin) cp "$system_root/etc/vconsole.conf" "$case_dir/image/etc/vconsole.conf" ;;
    compose) printf wrong >>"$case_dir/image/usr/share/X11/locale/en_US.UTF-8/Compose" ;;
    xkb-data) rm "$case_dir/image/usr/share/X11/xkb/symbols/us" ;;
    xkb-extra) printf override >"$case_dir/image/usr/share/X11/xkb/symbols/unknown" ;;
    xkb-library) printf wrong >>"$case_dir/image/usr/lib/libxkbcommon.so.0.1" ;;
    hook-payload) printf wrong >>"$case_dir/image/hooks/keymap" ;;
    hook-order) sed -i 's/plymouth keymap encrypt/plymouth encrypt keymap/' "$case_dir/image/config" ;;
    init-payload) printf wrong >>"$case_dir/image/init" ;;
    config-env) printf 'LANG=unknown\n' >>"$case_dir/image/config" ;;
    override) mkdir -p "$case_dir/image/etc/xkb" ;;
    symlink-map) rm "$case_dir/image/keymap.bin"; ln -s "$case_dir/expected/keymap.bin" "$case_dir/image/keymap.bin" ;;
    fifo-map) rm "$case_dir/image/keymap.bin"; mkfifo "$case_dir/image/keymap.bin" ;;
  esac
  if verify; then fail "$fault accepted"; fi
done
echo 'PASS: corrupt/missing map, Unicode marker, compose, XKB/default libraries, hooks, execution order and overrides fail closed'

# The engine must not retire the temporary slot when the real keyboard verifier rejects.
rekey_keyboard() { cat "$case_dir/expected/fingerprint"; }
rekey_build_boot() { :; }
rekey_verify_boot() { verify; }
stat() {
  local output
  output=$(command stat "$@") || return
  if [[ $2 == '%u:%a:%h' ]]; then printf '0:%s\n' "${output#*:}"
  else printf '%s\n' "$output"; fi
}
sync() { :; }
rekey_cryptsetup() {
  local op=$1 slot= key= arg
  local -a positional=()
  shift
  while (( $# )); do
    case $1 in
      --key-slot) slot=$2; shift 2 ;;
      --key-file) key=$2; shift 2 ;;
      --token-type) shift 2 ;;
      --*|-q) shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  case $op in
    luksUUID) echo 01234567-89ab-cdef-0123-456789abcdef ;;
    luksDump)
      printf 'Version: 2\nKeyslots:\n'
      for arg in "$case_dir"/slot-*; do [[ ! -f $arg ]] || printf '  %s: luks2\n' "${arg##*slot-}"; done ;;
    open) [[ -f $case_dir/slot-$slot && $(cat "$key") == "$(cat "$case_dir/slot-$slot")" ]] || return 2 ;;
    luksAddKey) cat "${positional[1]}" >"$case_dir/slot-$slot" ;;
    luksKillSlot) touch "$case_dir/revoked"; rm "$case_dir/slot-${positional[1]}" ;;
    *) return 90 ;;
  esac
}
make_case engine-bad-compose ru ru
PROVISIONING_DIR="$case_dir/state"
mkdir "$PROVISIONING_DIR"
printf fixture-temporary-key >"$PROVISIONING_DIR/luks-key"
chmod 600 "$PROVISIONING_DIR/luks-key"
cp "$PROVISIONING_DIR/luks-key" "$case_dir/slot-0"
password=fixture-owner-key
printf wrong >>"$case_dir/image/usr/share/X11/locale/en_US.UTF-8/Compose"
if luks_rekey /dev/fixture >"$case_dir/engine.log" 2>&1; then fail 'engine accepted stale compose'; fi
[[ ! -e $case_dir/revoked && -f $case_dir/slot-0 && -f $PROVISIONING_DIR/luks-key ]] || fail 'revocation occurred before keyboard proof'
cp "$system_root/usr/share/X11/locale/en_US.UTF-8/Compose" "$case_dir/image/usr/share/X11/locale/en_US.UTF-8/Compose"
luks_rekey /dev/fixture >"$case_dir/engine.log" 2>&1 || { cat "$case_dir/engine.log" >&2; fail 'keyboard repair retry'; }
[[ -e $case_dir/revoked && ! -e $case_dir/slot-0 ]] || fail 'repaired image did not finish'
echo 'PASS: real keyboard rejection prevents revocation; repairing the image resumes the journal'

old_fingerprint=$(<"$case_dir/expected/fingerprint")
printf 'KEYMAP=fr\nXKBLAYOUT=fr\n' >"$system_root/etc/vconsole.conf"
mkdir "$case_dir/new-keyboard"
rekey_keyboard_prepare "$case_dir/new-keyboard"
mv "$case_dir/expected" "$case_dir/old-keyboard"
mv "$case_dir/new-keyboard" "$case_dir/expected"
[[ $(<"$case_dir/expected/fingerprint") != "$old_fingerprint" ]] || fail 'layout did not change fingerprint'
if luks_rekey /dev/fixture >"$case_dir/engine.log" 2>&1; then fail 'done retry accepted old boot keyboard'; fi
cp "$case_dir/expected/keymap.bin" "$case_dir/image/keymap.bin"
cp "$case_dir/expected/vconsole.conf" "$case_dir/image/etc/vconsole.conf"
luks_rekey /dev/fixture >"$case_dir/engine.log" 2>&1 || { cat "$case_dir/engine.log" >&2; fail 'changed keyboard retry'; }
grep -qx "boot_layout=$(<"$case_dir/expected/fingerprint")" "$PROVISIONING_DIR/luks-rekey-state" || fail 'changed fingerprint not journaled'
echo 'PASS: done retry requires the rebuilt keyboard even after the provisional key was removed'

for case_dir in "$test_tmp"/bad-*; do
  PROVISIONING_DIR="$case_dir/state"
  mkdir "$PROVISIONING_DIR"
  printf fixture-temporary-key >"$PROVISIONING_DIR/luks-key"
  chmod 600 "$PROVISIONING_DIR/luks-key"
  cp "$PROVISIONING_DIR/luks-key" "$case_dir/slot-0"
  if luks_rekey /dev/fixture >"$case_dir/engine.log" 2>&1; then fail "engine accepted ${case_dir##*/}"; fi
  [[ ! -e $case_dir/revoked && -f $case_dir/slot-0 && -f $PROVISIONING_DIR/luks-key ]] || fail "revocation for ${case_dir##*/}"
done
echo 'PASS: every corrupt keyboard fixture prevents provisional-slot revocation in the real journal engine'
