#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
MONARCH_FACTORY_RESET_LIB_ONLY=true source "$ROOT/bin/monarch-system-factory-reset"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
old_id=11111111111111111111111111111111
new_id=33333333333333333333333333333333
LOG_FILE="$test_tmp/log"
gum() { :; }
log() { :; }

root="$test_tmp/menu"
mkdir -p "$root/etc" "$root/boot/EFI/Linux"
printf '%s\n' "$new_id" >"$root/etc/machine-id"
cat >"$root/boot/limine.conf" <<EOF
timeout: 7
default_entry: 2
/Windows
path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
/+Monarch
comment: machine-id=$old_id
//linux-cachyos
path: boot():/EFI/Linux/monarch_linux-cachyos.efi#aaaa
///snapshot
path: boot():/EFI/Linux/monarch_snapshot.efi#bbbb
/Foreign after
path: boot():/EFI/Linux/foreign_absent.efi#cccc
/Mixed
comment: machine-id=$old_id
//ours
path: boot():/EFI/Linux/monarch_recovery.efi#dddd
//theirs
path: boot():/EFI/Linux/other_recovery.efi#eeee
/Malformed
comment: machine-id=${old_id}g
path: boot():/EFI/Linux/monarch_old.efi#ffff
EOF
sed -n '/^\/Mixed/,$p' "$root/boot/limine.conf" >"$test_tmp/foreign"
reset_limine_config "$root" /boot "$old_id"
sed -n '/^\/Mixed/,$p' "$root/boot/limine.conf" >"$test_tmp/retained"
cmp "$test_tmp/foreign" "$test_tmp/retained"
[[ $(grep '^/' "$root/boot/limine.conf") == $'/Windows\n/+Monarch\n/Foreign after\n/Mixed\n//ours\n//theirs\n/Malformed' ]]
grep -qx 'default_entry: 2' "$root/boot/limine.conf"
grep -qx "comment: machine-id=$new_id" "$root/boot/limine.conf"
! grep -q '^///snapshot' "$root/boot/limine.conf"
if (verify_limine_hashes "$root" /boot); then
  echo 'accepted no local rebuilt image' >&2
  exit 1
fi
printf kernel >"$root/boot/EFI/Linux/monarch_linux-cachyos.efi"
hash=$(b2sum "$root/boot/EFI/Linux/monarch_linux-cachyos.efi" | cut -d' ' -f1)
sed -i "/machine-id=$new_id/a path: boot():/EFI/Linux/monarch_linux-cachyos.efi#$hash" "$root/boot/limine.conf"
verify_limine_hashes "$root" /boot
printf corrupt >"$root/boot/EFI/Linux/monarch_linux-cachyos.efi"
if (verify_limine_hashes "$root" /boot); then
  echo 'accepted corrupt local image' >&2
  exit 1
fi
for label in first second; do
  printf '/Duplicate %s\ncomment: machine-id=%s\npath: boot():/EFI/Linux/monarch_duplicate.efi#aaaa\n' "$label" "$old_id" >>"$root/boot/limine.conf"
done
cp "$root/boot/limine.conf" "$test_tmp/duplicate-menu"
if (reset_limine_config "$root" /boot "$old_id"); then exit 99; fi
cmp "$test_tmp/duplicate-menu" "$root/boot/limine.conf"

for mode in success first second rollback signal-before signal-between signal-after signal-hup restore-failure revoke-failure; do
  case_root="$test_tmp/$mode"
  mkdir -p "$case_root/top/@" "$case_root/top/@monarch-reset-next" \
    "$case_root/esp/EFI/Linux" "$case_root/backup"
  printf old >"$case_root/top/@/identity"
  printf new >"$case_root/top/@monarch-reset-next/identity"
  printf old-uki >"$case_root/esp/EFI/Linux/monarch_current.efi"
  backup_esp "$case_root/esp" "$case_root/backup"
  printf new-uki >"$case_root/esp/EFI/Linux/monarch_current.efi"
  printf factory-only >"$case_root/esp/EFI/Linux/factory-only.efi"
  mkdir -p "$case_root/esp/EFI/Microsoft"
  printf foreign >"$case_root/esp/EFI/Microsoft/boot.efi"
  set +e
  (
    set -e
    TOP_MNT="$case_root/top"
    next_owned=1
    top_owned=1
    esp_owned=1
    ESP_MNT="$case_root/esp"
    esp_backup="$case_root/backup"
    esp_restore=$ESP_MNT
    mountpoint() { [[ $2 == "$TOP_MNT" || $2 == "$ESP_MNT" ]]; }
    umount() { :; }
    btrfs() {
      [[ $1 == subvolume && $2 == delete && $4 == "$TOP_MNT/$NEXT_NAME" ]] || exit 91
      rm -rf -- "$4"
    }
    count=0
    mv() {
      count=$((count + 1))
      case "$mode:$count" in
        first:1|second:2|rollback:2|rollback:3|rollback:4) return 1 ;;
      esac
      command mv "$@"
      case "$mode:$count" in
        signal-between:1|signal-after:2) kill -TERM "$BASHPID" ;;
        signal-hup:1) kill -HUP "$BASHPID" ;;
      esac
    }
    if [[ $mode == restore-failure ]]; then
      cp() { return 1; }
    fi
    if [[ $mode == revoke-failure ]]; then
      revoke_reset_luks() { return 1; }
    fi
    trap cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    [[ $mode != signal-before ]] || kill -TERM "$BASHPID"
    [[ $mode != restore-failure ]] || exit 1
    [[ $mode != revoke-failure ]] || exit 1
    activate_factory_root
  ) >"$case_root/output" 2>&1
  status=$?
  set -e
  case $mode in
    success|signal-after)
      [[ $(<"$case_root/top/@/identity") == new ]]
      [[ $(<"$case_root/esp/EFI/Linux/monarch_current.efi") == new-uki ]]
      [[ -e $case_root/esp/EFI/Linux/factory-only.efi ]]
      [[ ! -e $case_root/backup ]]
      ;;
    rollback)
      ((status != 0))
      [[ ! -d $case_root/top/@ && -d $case_root/top/@monarch-reset-next ]]
      compgen -G "$case_root/top/@monarch-old-*/identity" >/dev/null
      grep -q 'live USB' "$case_root/output"
      ;;
    restore-failure)
      ((status != 0))
      [[ -e $case_root/backup/EFI/Linux/monarch_current.efi && -d $case_root/top/@monarch-reset-next ]]
      grep -q 'copies retained' "$case_root/output"
      ;;
    revoke-failure)
      ((status != 0))
      [[ -d $case_root/top/@monarch-reset-next && -d $case_root/top/@ ]]
      [[ $(<"$case_root/esp/EFI/Linux/monarch_current.efi") == old-uki ]]
      ;;
    *)
      ((status != 0))
      [[ $(<"$case_root/top/@/identity") == old ]]
      [[ $(<"$case_root/esp/EFI/Linux/monarch_current.efi") == old-uki ]]
      [[ ! -e $case_root/esp/EFI/Linux/factory-only.efi ]]
      [[ ! -d $case_root/top/@monarch-reset-next ]]
      ;;
  esac
  case $mode in
    signal-hup) ((status == 129)) ;;
    signal-*) ((status == 143)) ;;
  esac
  [[ $(<"$case_root/esp/EFI/Microsoft/boot.efi") == foreign ]]
done

(
  TOP_MNT="$test_tmp/activated-unmounted"
  ESP_MNT="$test_tmp/activated-esp"
  root_activated=1
  revoke_reset_luks() { exit 99; }
  cleanup
)

(
  TOP_MNT="$test_tmp/prior-staging"
  mkdir -p "$TOP_MNT/@" "$TOP_MNT/$NEXT_NAME"
  top_owned=1
  mountpoint() { [[ $2 == "$TOP_MNT" ]]; }
  umount() { :; }
  btrfs() { exit 99; }
  if (stage_full_reset); then exit 98; fi
  cleanup
  [[ -d $TOP_MNT/$NEXT_NAME ]]
)

(
  ESP_MNT="$test_tmp/identity-esp"
  mkdir -p "$ESP_MNT/$old_id"
  touch "$ESP_MNT/$old_id/shared"
  esp_old_id=$old_id
  esp_new_id=$new_id
  printf '/Other installation\ncomment: machine-id=%s\n' "$old_id" >"$ESP_MNT/limine.conf"
  commit_esp_staging
  [[ -f $ESP_MNT/$old_id/shared ]]
  printf '/Other installation\npath: boot():/%s/foreign.efi\n' "$old_id" >"$ESP_MNT/limine.conf"
  commit_esp_staging
  [[ -f $ESP_MNT/$old_id/shared ]]
  printf '/Monarch\ncomment: machine-id=%s\n' "$new_id" >"$ESP_MNT/limine.conf"
  commit_esp_staging
  [[ ! -e $ESP_MNT/$old_id ]]
  mkdir -p "$ESP_MNT/$old_id"
  touch "$ESP_MNT/$old_id/shared"
  rm "$ESP_MNT/limine.conf"
  if commit_esp_staging 2>/dev/null; then exit 99; fi
  [[ -f $ESP_MNT/$old_id/shared ]]
)

for mode in rebuild-error corrupt no-local backup-failure; do
  case_root="$test_tmp/prepare-$mode"
  mkdir -p "$case_root/top/@" "$case_root/top/@monarch-reset-next/etc" "$case_root/esp/EFI/Linux"
  next="$case_root/top/@monarch-reset-next"
  printf '%s\n' "$new_id" >"$next/etc/machine-id"
  touch "$case_root/device"
  printf '%s /boot vfat defaults 0 2\n' "$case_root/device" >"$next/etc/fstab"
  printf original >"$case_root/esp/EFI/Linux/monarch_current.efi"
  cat >"$case_root/esp/limine.conf" <<EOF
/Monarch
comment: machine-id=$old_id
//linux-cachyos
path: boot():/EFI/Linux/monarch_current.efi#aaaa
/Foreign
path: boot():/EFI/Linux/foreign_absent.efi#bbbb
EOF
  cp "$case_root/esp/limine.conf" "$case_root/original.conf"
  set +e
  (
    set -e
    TOP_MNT="$case_root/top"
    ESP_MNT="$case_root/esp"
    ORIGINAL_MACHINE_ID=$old_id
    next_owned=1
    top_owned=1
    mountpoint() { [[ $2 == "$TOP_MNT" || ( $2 == "$ESP_MNT" && $esp_owned == 1 ) ]]; }
    mount() {
      if [[ $1 == --bind ]]; then ln -s "$ESP_MNT" "$next/boot"; fi
    }
    umount() { :; }
    btrfs() { [[ $1 == subvolume && $2 == delete && $4 == "$next" ]] || exit 91; rm -rf -- "$4"; }
    mktemp() {
      if [[ ${2:-} == /var/tmp/monarch-system-factory-reset-esp.* ]]; then
        command mktemp -d "$case_root/backup.XXXXXX"
      else command mktemp "$@"; fi
    }
    cp() { [[ $mode != backup-failure ]] || return 1; command cp "$@"; }
    chroot() {
      [[ $2 == /usr/bin/limine-update ]] || exit 97
      printf rebuilt >"$ESP_MNT/EFI/Linux/monarch_current.efi"
      printf addition >"$ESP_MNT/EFI/Linux/factory-only.efi"
      [[ $mode != rebuild-error ]] || return 1
      [[ $mode != no-local ]] || return 0
      hash=$(b2sum "$ESP_MNT/EFI/Linux/monarch_current.efi" | cut -d' ' -f1)
      printf '\n/Monarch rebuilt\ncomment: machine-id=%s\npath: boot():/EFI/Linux/monarch_current.efi#%s\n' "$new_id" "$hash" >>"$ESP_MNT/limine.conf"
      printf corrupt >"$ESP_MNT/EFI/Linux/monarch_current.efi"
    }
    trap cleanup EXIT
    rebuild_next_boot "$next"
  ) >"$case_root/output" 2>&1
  status=$?
  set -e
  ((status != 0))
  [[ $(<"$case_root/esp/EFI/Linux/monarch_current.efi") == original ]]
  [[ ! -e $case_root/esp/EFI/Linux/factory-only.efi ]]
  cmp "$case_root/original.conf" "$case_root/esp/limine.conf"
done

(
  RESET_LUKS_ADDED=1
  RESET_LUKS_DEVICE="$test_tmp/fake-device"
  RESET_LUKS_AUTH='fixture authorization only'
  RESET_THROWAWAY='fixture temporary only'
  RESET_LUKS_SLOT=7
  cryptsetup() {
    local arg previous='' key='' token=false
    for arg in "$@"; do
      [[ $arg != "$RESET_LUKS_AUTH" && $arg != "$RESET_THROWAWAY" ]] || exit 92
      [[ $previous != --key-file ]] || key=$(cat "$arg")
      [[ $arg != passphrase-only ]] || token=true
      previous=$arg
    done
    if [[ $1 == open ]]; then
      [[ $token == true ]] || exit 93
      [[ $key == "$RESET_LUKS_AUTH" || $key == "$RESET_THROWAWAY" ]] || exit 94
      [[ ${wrong_slot:-false} != true ]] || { echo 'Key slot 8 unlocked'; return; }
      echo 'Key slot 7 unlocked'
    else
      [[ $1 == luksKillSlot && ${!#} == 7 && $key == "$RESET_LUKS_AUTH" ]] || exit 95
      touch "$test_tmp/revoked"
    fi
  }
  wrong_slot=true
  if revoke_reset_luks; then exit 96; fi
  [[ ! -e $test_tmp/revoked ]]
  wrong_slot=false
  revoke_reset_luks
  [[ -e $test_tmp/revoked && $RESET_LUKS_ADDED == 0 ]]
)

(
  root="$test_tmp/staged-key"
  device="$test_tmp/staged-device"
  touch "$device"
  luks_device() { printf '%s\n' "$test_tmp/staged-device"; }
  generate_passphrase() { printf 'fixture temporary only'; }
  gum() { [[ $1 != input ]] || printf 'fixture authorization only'; }
  cryptsetup() {
    local arg previous='' key=''
    for arg in "$@"; do
      [[ $arg != 'fixture temporary only' && $arg != 'fixture authorization only' ]] || exit 92
      [[ $previous != --key-file ]] || key=$(cat "$arg")
      previous=$arg
    done
    if env | grep -qE 'fixture (temporary|authorization) only'; then exit 93; fi
    case $1 in
      open)
        [[ $* == *'--token-type passphrase-only'* ]] || exit 94
        [[ $key == 'fixture temporary only' || $key == 'fixture authorization only' ]] || exit 95
        echo 'Key slot 7 unlocked'
        ;;
      luksAddKey)
        [[ $key == 'fixture authorization only' && $(cat "${!#}") == 'fixture temporary only' ]] || exit 96
        ;;
      luksKillSlot) [[ ${!#} == 7 ]] || exit 97 ;;
      *) exit 98 ;;
    esac
  }
  export current=decoy passphrase=decoy
  set -x
  stage_luks_rekey "$root"
  set +x
  [[ $RESET_LUKS_SLOT == 7 ]]
  [[ $(stat -c %a "$root$PROVISIONING_DIR/luks-key") == 600 ]]
  [[ $(stat -c %a "$root/etc/monarch/provisioning.key") == 600 ]]
  [[ $(<"$root$PROVISIONING_DIR/luks-key") == 'fixture temporary only' ]]
  revoke_reset_luks
) >"$test_tmp/secret-transport.log" 2>&1
! grep -qE 'fixture (temporary|authorization) only' "$test_tmp/secret-transport.log"

if ((EUID != 0)); then
  mkdir -p "$test_tmp/elevation/checkout with spaces" "$test_tmp/elevation/bin"
  reset="$test_tmp/elevation/checkout with spaces/reset"
  packaged="$test_tmp/elevation/packaged"
  sudo_stub="$test_tmp/elevation/bin/sudo"
  awk '/^log\(\) / { print "exit 99"; exit } { print }' "$ROOT/bin/monarch-system-factory-reset" |
    sed -e "s|PACKAGED_RESET=/usr/bin/monarch-system-factory-reset|PACKAGED_RESET=\"$packaged\"|" \
      -e "s|exec /usr/bin/sudo |exec \"$sudo_stub\" |" >"$reset"
  cp "$reset" "$packaged"
  cat >"$sudo_stub" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$CALL_LOG"
exit "$SUDO_STATUS"
EOF
  chmod +x "$reset" "$packaged" "$sudo_stub"
  ln -s "$reset" "$test_tmp/elevation/bin/reset-link"
  args=('argument with spaces' '' $'two\nlines')
  for invocation in "$reset" "$packaged" reset-link; do
    for code in 0 1 127; do
      status=0
      env -i PATH="$test_tmp/elevation/bin:/usr/bin" CALL_LOG="$test_tmp/call" SUDO_STATUS="$code" \
        MONARCH_PATH=/untrusted GUM_INPUT_PROMPT=$'Reset\nthis computer?' GUM_STYLE='' \
        NON_GUM=$'note\nGUM_FAKE=not a variable' "$invocation" "${args[@]}" || status=$?
      ((status == code))
      mapfile -d '' -t actual <"$test_tmp/call"
      [[ ${actual[0]} == /usr/bin/env && ${actual[1]} == -- ]]
      [[ ${actual[2]} == GUM_* && ${actual[3]} == GUM_* ]]
      [[ ${actual[2]} == $'GUM_INPUT_PROMPT=Reset\nthis computer?' || ${actual[3]} == $'GUM_INPUT_PROMPT=Reset\nthis computer?' ]]
      [[ ${actual[2]} == GUM_STYLE= || ${actual[3]} == GUM_STYLE= ]]
      expected=("$packaged" "${args[@]}")
      ((${#actual[@]} == ${#expected[@]} + 4))
      for i in "${!expected[@]}"; do [[ ${actual[i+4]} == "${expected[i]}" ]]; done
    done
  done
  env -i CALL_LOG="$test_tmp/call" SUDO_STATUS=0 "$reset" "${args[@]}"
  mapfile -d '' -t actual <"$test_tmp/call"
  ((${#actual[@]} == ${#args[@]} + 3))
  [[ ${actual[2]} == "$packaged" ]]
  printf '\n# divergent copy\n' >>"$packaged"
  rm "$test_tmp/call"
  if env -i CALL_LOG="$test_tmp/call" SUDO_STATUS=0 "$reset" >"$test_tmp/mismatch" 2>&1; then exit 98; fi
  [[ ! -e $test_tmp/call ]]
else
  echo 'SKIP: elevation requires an unprivileged caller'
fi

echo 'factory reset transaction: ok'
