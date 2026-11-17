# Provisioning retires every non-owner slot, unlike a manual password change.
# The caller supplies password, PROVISIONING_DIR, log_step, luks_device and
# reset_limine_config. Sourcing has no effects; secrets never enter the journal.

rekey_private_path() {
  local path=$1 mode uid
  [[ ! -L $path ]] || return 1
  read -r uid mode < <(stat -c '%u %a' -- "$path") || return 1
  [[ $uid == 0 && $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 ))
}

rekey_cryptsetup() {
  local status
  if timeout --kill-after=5s 120s cryptsetup "$@"; then
    return 0
  else
    status=$?
    if (( status == 124 || status == 137 )); then
      echo "Disk encryption operation timed out; provisioning remains pending for retry" >&2
    fi
    return "$status"
  fi
}

rekey_slots() {
  local dump
  dump=$(LC_ALL=C rekey_cryptsetup luksDump "$1") || return 1
  awk '
    /^Version:/ { version = $2 }
    /^[^ \t]/ { section = ($0 == "Keyslots:") }
    section && /^ +[0-9]+: luks2/ { sub(":", "", $1); slots[++n] = $1 }
    /^Key Slot [0-9]+: ENABLED/ { sub(":", "", $3); slots[++n] = $3 }
    END {
      if ((version != 1 && version != 2) || !n) exit 1
      for (i = 1; i <= n; i++) {
        if (slots[i] !~ /^[0-9]+$/ || slots[i] + 0 >= (version == 1 ? 8 : 32)) exit 1
        print slots[i]
      }
    }' <<<"$dump" | sort -nu
}

rekey_slot_limit() {
  local dump version
  dump=$(LC_ALL=C rekey_cryptsetup luksDump "$1") || return 1
  version=$(awk '/^Version:/ { print $2 }' <<<"$dump")
  case $version in
    1) printf '8\n' ;;
    2) printf '32\n' ;;
    *) return 1 ;;
  esac
}

# Status 2 means a rejected passphrase; all other errors stop the transition.
rekey_probe() {
  local status
  if rekey_cryptsetup open --test-passphrase --token-type passphrase-only --disable-external-tokens \
    --key-slot "$2" --key-file "$3" "$1" >/dev/null; then
    return 0
  else
    status=$?
    (( status == 2 )) && return 2
    return 1
  fi
}

rekey_write() {
  local tmp
  tmp=$(mktemp "$PROVISIONING_DIR/.luks-rekey.XXXXXX") || return 1
  if printf 'version=1\nuuid=%s\nstaged_slot=%s\nowner_slot=%s\nphase=%s\nboot_layout=%s\n' \
    "$rekey_uuid" "$rekey_staged" "$rekey_owner" "$rekey_phase" "$rekey_layout" >"$tmp" &&
    chmod 600 "$tmp" && sync "$tmp" && mv -fT -- "$tmp" "$REKEY_STATE" && sync "$PROVISIONING_DIR"; then
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

rekey_read() {
  local key value count=0
  local -A seen=()
  [[ -f $REKEY_STATE && ! -L $REKEY_STATE && $(stat -c '%u:%a:%h' "$REKEY_STATE") == "0:600:1" ]] || return 1
  while IFS='=' read -r key value; do
    [[ -n $key && ! ${seen[$key]+present} ]] || return 1
    seen[$key]=1
    (( count += 1 ))
    case $key in
      version) [[ $value == 1 ]] || return 1 ;;
      uuid) [[ $value == "$rekey_uuid" ]] || return 1 ;;
      staged_slot) [[ $value =~ ^([0-9]|[12][0-9]|3[01])$ ]] || return 1; rekey_staged=$value ;;
      owner_slot) [[ $value =~ ^([0-9]|[12][0-9]|3[01])$ ]] || return 1; rekey_owner=$value ;;
      phase) [[ $value =~ ^(staged|owner|boot|done)$ ]] || return 1; rekey_phase=$value ;;
      boot_layout) [[ $value == - || $value =~ ^[0-9a-f]{64}$ ]] || return 1; rekey_layout=$value ;;
      *) return 1 ;;
    esac
  done <"$REKEY_STATE"
  (( count == 6 )) && [[ $rekey_owner != "$rekey_staged" ]] || return 1
  [[ $rekey_phase == staged || $rekey_phase == owner || $rekey_layout != - ]]
}

rekey_keyboard_prepare() (
  set -euo pipefail
  export PATH=/usr/bin:/bin
  local output=$1 config copied=false keymap unicode=false
  local KEYMAP KEYMAP_TOGGLE FONT FONT_MAP FONT_UNIMAP XKBLAYOUT XKBMODEL XKBVARIANT XKBOPTIONS
  local LANG= LOCALE= LC_ALL= LC_CTYPE=
  local -a FILES=() HOOKS=() MODULES=() configs=(/etc/mkinitcpio.conf)
  rekey_private_path /etc || return 1
  rekey_private_path /etc/mkinitcpio.conf.d || return 1
  rekey_private_path /etc/vconsole.conf || return 1
  source /etc/vconsole.conf || return 1
  keymap=${KEYMAP:-us}
  [[ $keymap =~ ^[a-zA-Z0-9_+.-]+$ ]] || return 1
  [[ ${keyboard:-$keymap} == "$keymap" ]] || return 1
  if [[ -e /etc/locale.conf ]]; then
    rekey_private_path /etc/locale.conf || return 1
    source /etc/locale.conf || return 1
  fi
  LOCALE=${LANG:-${LOCALE:-C}}
  [[ $LOCALE != *[Uu][Tt][Ff]?(-)8 ]] || unicode=true
  add_file() { copied=true; }
  while IFS= read -r -d '' config; do configs+=("$config"); done < <(
    find /etc/mkinitcpio.conf.d -maxdepth 1 -xtype f -name '*.conf' -print0 | LC_ALL=C.UTF-8 sort -zVu
  )
  for config in "${configs[@]}"; do rekey_private_path "$config" || return 1; done
  source <(cat -- "${configs[@]}") || return 1
  [[ " ${HOOKS[*]} " == *" keymap "* && " ${HOOKS[*]} " == *" plymouth "* ]] || return 1
  if [[ " ${FILES[*]} " == *" /etc/vconsole.conf "* ]]; then copied=true; fi
  # Plymouth's install hook has its own FILES array; the packaged guard still
  # blocks its implicit copy, while an explicit global FILES entry wins later.
  local -a FILES=()
  add_file /etc/vconsole.conf || return 1
  local -a options=(-q)
  if $unicode; then options+=(-u); touch "$output/keymap.utf8"; fi
  (cd / && loadkeys "${options[@]}" "$keymap" -b) >"$output/keymap.bin" || return 1
  [[ -s $output/keymap.bin ]] || return 1
  if $copied; then cp /etc/vconsole.conf "$output/vconsole.conf" || return 1; fi
  python3 - "$output" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

system = Path("/")
output = Path(sys.argv[1])
entries = {}

def record(source, destination):
    path = system / source
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode):
        target = os.readlink(path)
        resolved = (system / target.lstrip("/")) if target.startswith("/") else path.parent / target
        resolved = resolved.resolve(strict=True)
        resolved.relative_to(system.resolve())
        entries[destination] = ["link", target]
        record(str(resolved.relative_to(system)), str(resolved.relative_to(system)))
    elif stat.S_ISREG(info.st_mode):
        entries[destination] = ["file", hashlib.sha256(path.read_bytes()).hexdigest(), bool(info.st_mode & 0o111)]
    else:
        raise ValueError("unsupported keyboard artifact")

trees = ("usr/share/X11/xkb", "usr/share/X11/locale")
for tree in trees:
    directory = system / tree
    if directory.is_symlink():
        # CachyOS ships xkb as a symlink to xkeyboard-config-2; the image keeps
        # the logical path, so record logical names while reading the target.
        walked = directory.resolve(strict=True)
        walked.relative_to(system.resolve())
        if not walked.is_dir():
            raise ValueError("missing keyboard data directory")
    elif directory.is_dir():
        walked = directory
    else:
        raise ValueError("missing keyboard data directory")
    for parent, directories, files in os.walk(walked, followlinks=False):
        for name in directories[:] + files:
            path = Path(parent) / name
            logical = str(Path(tree) / path.relative_to(walked))
            if path.is_symlink():
                target = os.readlink(path)
                entries[logical] = ["link", target]
                resolved = (path.parent / target).resolve(strict=True) if not target.startswith("/") else Path(target).resolve(strict=True)
                resolved.relative_to(system.resolve())
                try:
                    mapped = str(Path(tree) / resolved.relative_to(walked))
                except ValueError:
                    mapped = str(resolved.relative_to(system.resolve()))
                info = resolved.lstat()
                entries[mapped] = ["file", hashlib.sha256(resolved.read_bytes()).hexdigest(), bool(info.st_mode & 0o111)]
            elif path.is_file():
                info = path.lstat()
                entries[logical] = ["file", hashlib.sha256(path.read_bytes()).hexdigest(), bool(info.st_mode & 0o111)]
            elif not path.is_dir():
                raise ValueError("unsupported keyboard artifact")
    if not any(name.startswith(tree + "/") for name in entries):
        raise ValueError("empty keyboard data directory")

for source, destination in (
    ("usr/lib/initcpio/init", "init"),
    ("usr/lib/initcpio/init_functions", "init_functions"),
    ("usr/lib/initcpio/hooks/keymap", "hooks/keymap"),
    ("usr/lib/initcpio/hooks/plymouth", "hooks/plymouth"),
    ("usr/lib/initcpio/hooks/encrypt", "hooks/encrypt"),
    ("usr/bin/plymouthd", "usr/bin/plymouthd"),
    ("usr/bin/plymouth", "usr/bin/plymouth"),
):
    record(source, destination)
    if destination == "init" or destination.startswith("hooks/"):
        entries[destination][2] = True
for source in ("usr/lib/libply-splash-core.so.5", "usr/lib/libxkbcommon.so.0"):
    record(source, source)

manifest = {"entries": entries, "trees": trees, "vconsole": (output / "vconsole.conf").exists(),
            "unicode": (output / "keymap.utf8").exists()}
(output / "expected.json").write_text(json.dumps(manifest, sort_keys=True))
digest = hashlib.sha256()
digest.update(json.dumps(manifest, sort_keys=True).encode())
for path in (system / "etc/vconsole.conf", system / "etc/locale.conf", output / "keymap.bin"):
    digest.update(path.read_bytes() if path.exists() else b"missing")
(output / "fingerprint").write_text(digest.hexdigest() + "\n")
PY
)

rekey_keyboard() (
  local tmp
  tmp=$(mktemp -d /run/monarch-rekey-keyboard.XXXXXX) || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  rekey_keyboard_prepare "$tmp" && cat "$tmp/fingerprint"
)

rekey_verify_keyboard() {
  python3 - "$1" "$2" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys

root, expected = map(Path, sys.argv[1:])
manifest = json.loads((expected / "expected.json").read_text())
for override in ("etc/xkb", "etc/X11/xkb", "root/.config/xkb", "root/.XCompose", ".config/xkb", ".XCompose"):
    path = root / override
    if path.exists() or path.is_symlink():
        raise ValueError("unverified keyboard or compose override")

def checked(path):
    relative = path.relative_to(root)
    parent = root
    for component in relative.parts[:-1]:
        parent /= component
        if parent.is_symlink():
            raise ValueError("symlinked keyboard parent")
    if not path.is_symlink():
        path.resolve(strict=True).relative_to(root.resolve())
    return path

def regular(path):
    checked(path)
    if path.is_symlink() or not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("non-regular keyboard artifact")
    return path

def entry_path(relative):
    for tree in manifest["trees"]:
        if relative.startswith(tree + "/"):
            directory = root / tree
            if directory.is_symlink():
                walked = directory.resolve(strict=True)
                walked.relative_to(root.resolve())
                return checked(walked / relative[len(tree) + 1:])
            break
    return checked(root / relative)

for relative, value in manifest["entries"].items():
    path = entry_path(relative)
    info = path.lstat()
    if value[0] == "link":
        if not path.is_symlink() or os.readlink(path) != value[1]:
            raise ValueError("keyboard symlink differs")
    elif not stat.S_ISREG(info.st_mode) or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != value[1] or bool(info.st_mode & 0o111) != value[2]:
        raise ValueError("keyboard artifact differs: " + relative)
for tree in manifest["trees"]:
    directory = root / tree
    if directory.is_symlink():
        walked = directory.resolve(strict=True)
        walked.relative_to(root.resolve())
        if not walked.is_dir():
            raise ValueError("symlinked keyboard tree is not a directory")
    else:
        walked = checked(directory)
    actual = set()
    for parent, directories, files in os.walk(walked, followlinks=False):
        for name in directories[:] + files:
            path = Path(parent) / name
            if path.is_symlink() or path.is_file():
                actual.add(str(Path(tree) / path.relative_to(walked)))
    if actual != {name for name in manifest["entries"] if name.startswith(tree + "/")}:
        raise ValueError("keyboard data inventory differs")
if regular(root / "keymap.bin").read_bytes() != (expected / "keymap.bin").read_bytes():
    raise ValueError("compiled console keymap differs")
marker = root / "keymap.utf8"
if marker.is_symlink() or marker.exists() != manifest["unicode"]:
    raise ValueError("console Unicode mode differs")
if manifest["unicode"] and regular(marker).stat().st_size != 0:
    raise ValueError("invalid console Unicode marker")
vconsole = root / "etc/vconsole.conf"
if manifest["vconsole"]:
    if regular(vconsole).read_bytes() != (expected / "vconsole.conf").read_bytes():
        raise ValueError("Plymouth console configuration differs")
elif vconsole.exists() or vconsole.is_symlink():
    raise ValueError("Plymouth non-Latin fallback was overridden")
config = {}
for line in regular(root / "config").read_text().splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    match = re.fullmatch(r'(MODULES|EARLYHOOKS|HOOKS|LATEHOOKS|CLEANUPHOOKS|EMERGENCYHOOKS)=(.*)', line)
    if not match or match[1] in config:
        raise ValueError("unverified initramfs execution configuration")
    values = shlex.split(match[2])
    if len(values) != 1 or not re.fullmatch(r'[a-zA-Z0-9_ -]*', values[0]):
        raise ValueError("invalid initramfs hook list")
    config[match[1]] = values[0].split()
hooks = config.get("HOOKS", [])
if not all(hook in hooks for hook in ("keymap", "plymouth", "encrypt")) or hooks.index("keymap") > hooks.index("encrypt") or hooks.index("plymouth") > hooks.index("encrypt"):
    raise ValueError("keyboard hooks do not precede disk unlock")
PY
}

rekey_unlock_present() {
  local file
  for file in /etc/monarch/provisioning.key \
    /etc/limine-entry-tool.d/99-monarch-provisioning-unlock.conf \
    /etc/mkinitcpio.conf.d/99-monarch-provisioning-key.conf; do
    [[ ! -e $file && ! -L $file ]] || return 0
  done
  return 1
}

# Inspect the artifacts Limine actually references, not just the build status.
rekey_verify_boot() (
  set -euo pipefail
  local esp id references ref path hash tmp count=0 listing
  ! rekey_unlock_present || return 1
  esp=$(esp_path)
  id=$(cat /etc/machine-id)
  [[ $id =~ ^[0-9a-f]{32}$ && $esp == /* && -f $esp/limine.conf ]] || return 1
  references=$(awk -v id="$id" '
    /^\/[^\/]/ { mine = 0 }
    $0 ~ ("^[[:space:]]*comment:[[:space:]]*machine-id=" id "([[:space:]]|$)") { mine = 1 }
    mine && /^[[:space:]]*path:/ { print $2 }
  ' "$esp/limine.conf") || return 1
  [[ -n $references ]] || return 1
  tmp=$(mktemp -d /run/monarch-rekey-boot.XXXXXX) || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  mkdir "$tmp/keyboard" || return 1
  rekey_keyboard_prepare "$tmp/keyboard" || return 1
  while IFS= read -r ref; do
    [[ $ref =~ ^boot\(\):/EFI/Linux/monarch_[a-zA-Z0-9_.-]+\.efi#[0-9a-f]{128}$ ]] || return 1
    path=${ref#boot():}; path=${path%#*}; hash=${ref##*#}
    [[ -f $esp$path && ! -L $esp$path ]] || return 1
    [[ $(b2sum "$esp$path" | cut -d' ' -f1) == "$hash" ]] || return 1
    rm -f -- "$tmp/initrd" "$tmp/cmdline"
    objcopy --dump-section ".initrd=$tmp/initrd" --dump-section ".cmdline=$tmp/cmdline" \
      "$esp$path" "$tmp/image" >/dev/null 2>&1 || return 1
    [[ -s $tmp/initrd && -s $tmp/cmdline ]] || return 1
    ! grep -aEq 'cryptkey=|rd\.luks\.key=|provisioning\.key' "$tmp/cmdline" || return 1
    ! grep -aEq '(^|[[:space:]])(disablehooks=|rd\.vconsole\.|vconsole\.|rd\.locale\.|locale\.|LANG=|LC_[A-Z_]*=|XKB_[A-Z_]*=|XCOMPOSEFILE=|HOME=|XDG_[A-Z_]*=)' "$tmp/cmdline" || return 1
    listing=$(lsinitcpio "$tmp/initrd") || return 1
    ! grep -qE '(^|/)provisioning\.key$' <<<"$listing" || return 1
    mkdir "$tmp/extract"
    (cd "$tmp/extract" && lsinitcpio -x "$tmp/initrd" >/dev/null) || return 1
    rekey_verify_keyboard "$tmp/extract" "$tmp/keyboard" || return 1
    rm -rf -- "$tmp/extract"
    count=$((count + 1))
  done <<<"$references"
  (( count > 0 ))
)

rekey_build_boot() {
  rm -f /etc/monarch/provisioning.key \
    /etc/limine-entry-tool.d/99-monarch-provisioning-unlock.conf \
    /etc/mkinitcpio.conf.d/99-monarch-provisioning-key.conf || return 1
  reset_limine_config && limine-update && rekey_verify_boot && sync
}

luks_rekey_pending() {
  [[ -e $PROVISIONING_DIR/luks-key || -L $PROVISIONING_DIR/luks-key ||
    -e $PROVISIONING_DIR/luks-rekey-state || -L $PROVISIONING_DIR/luks-rekey-state ]] || rekey_unlock_present
}

luks_rekey() (
  set +x
  set -euo pipefail
  umask 077
  export -n password
  local device=$1 REKEY_STATE="$PROVISIONING_DIR/luks-rekey-state"
  local rekey_uuid rekey_staged= rekey_owner= rekey_phase=staged rekey_layout=-
  local slots slot status layout lock_fd drive_lock_fd candidate parent limit
  exec {drive_lock_fd}>/run/monarch-drive-password.lock
  flock -n "$drive_lock_fd" || return 1
  # The service uses a packaged helper and a fixed root-owned state directory.
  parent=$PROVISIONING_DIR
  while [[ $parent != / ]]; do
    rekey_private_path "$parent" || return 1
    parent=${parent%/*}; [[ -n $parent ]] || parent=/
  done
  [[ ! -L $PROVISIONING_DIR/luks-rekey.lock ]] || return 1
  exec {lock_fd}>"$PROVISIONING_DIR/luks-rekey.lock"
  rekey_private_path "$PROVISIONING_DIR/luks-rekey.lock" || return 1
  flock -n "$lock_fd" || return 1
  rekey_uuid=$(rekey_cryptsetup luksUUID "$device") || return 1
  [[ $rekey_uuid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 1
  [[ ! -e /var/lib/monarch-drive-password/$rekey_uuid.json && ! -L /var/lib/monarch-drive-password/$rekey_uuid.json ]] || return 1
  slots=$(rekey_slots "$device") || return 1
  limit=$(rekey_slot_limit "$device") || return 1
  layout=$(rekey_keyboard) || return 1
  [[ $layout =~ ^[0-9a-f]{64}$ ]] || return 1
  if [[ -e $PROVISIONING_DIR/luks-key || -L $PROVISIONING_DIR/luks-key ]]; then
    [[ -f $PROVISIONING_DIR/luks-key && ! -L $PROVISIONING_DIR/luks-key &&
      $(stat -c '%u:%a:%h' "$PROVISIONING_DIR/luks-key") == "0:600:1" ]] || return 1
  fi
  if [[ -e $REKEY_STATE || -L $REKEY_STATE ]]; then
    rekey_read || return 1
    (( rekey_staged < limit && rekey_owner < limit )) || return 1
  else
    [[ -f $PROVISIONING_DIR/luks-key ]] || return 1
    for slot in $slots; do
      if rekey_probe "$device" "$slot" "$PROVISIONING_DIR/luks-key"; then
        rekey_staged=$slot
        break
      else
        status=$?; (( status == 2 )) || return 1
      fi
    done
    [[ -n $rekey_staged ]] || return 1
    for ((candidate = 0; candidate < limit; candidate++)); do
      if ! grep -qx "$candidate" <<<"$slots"; then rekey_owner=$candidate; break; fi
    done
    [[ -n $rekey_owner ]] || return 1
    rekey_write || return 1
  fi
  if grep -qx "$rekey_owner" <<<"$slots"; then
    rekey_probe "$device" "$rekey_owner" <(printf '%s' "$password") || return 1
  else
    [[ $rekey_phase == staged && -f $PROVISIONING_DIR/luks-key ]] || return 1
    rekey_probe "$device" "$rekey_staged" "$PROVISIONING_DIR/luks-key" || return 1
    if rekey_probe "$device" "$rekey_staged" <(printf '%s' "$password"); then return 1
    else status=$?; (( status == 2 )) || return 1; fi
    rekey_cryptsetup luksAddKey --key-slot "$rekey_owner" --key-file "$PROVISIONING_DIR/luks-key" \
      "$device" <(printf '%s' "$password") || return 1
    sync || return 1
    rekey_probe "$device" "$rekey_owner" <(printf '%s' "$password") || return 1
  fi
  # A duplicate temporary secret must never become the sole surviving owner key.
  if [[ -f $PROVISIONING_DIR/luks-key ]]; then
    if rekey_probe "$device" "$rekey_owner" "$PROVISIONING_DIR/luks-key"; then return 1
    else status=$?; (( status == 2 )) || return 1; fi
  fi
  if [[ $rekey_phase == staged ]]; then
    rekey_phase=owner; rekey_write || return 1
  fi
  if [[ $rekey_phase == owner || $rekey_layout != "$layout" ]] || rekey_unlock_present; then
    rekey_build_boot || return 1
    rekey_layout=$layout
    [[ $rekey_phase == done ]] || rekey_phase=boot
    rekey_write || return 1
  fi
  rekey_verify_boot || return 1
  [[ $(rekey_keyboard) == "$rekey_layout" ]] || return 1
  slots=$(rekey_slots "$device") || return 1
  if [[ $rekey_phase == done && $slots != "$rekey_owner" ]]; then return 1; fi
  for slot in $slots; do
    [[ $slot == "$rekey_owner" ]] && continue
    rekey_probe "$device" "$rekey_owner" <(printf '%s' "$password") || return 1
    rekey_cryptsetup luksKillSlot -q --key-file <(printf '%s' "$password") "$device" "$slot" || return 1
    sync || return 1
  done
  [[ $(rekey_slots "$device") == "$rekey_owner" ]] || return 1
  rekey_probe "$device" "$rekey_owner" <(printf '%s' "$password") || return 1
  rekey_verify_boot || return 1
  rm -f -- "$PROVISIONING_DIR/luks-key" || return 1
  sync "$PROVISIONING_DIR" || return 1
  rekey_phase=done; rekey_write
)
