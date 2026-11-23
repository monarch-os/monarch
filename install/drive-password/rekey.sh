#!/bin/bash -p

# Only the fixed packaged path is elevated; -p suppresses BASH_ENV/functions before startup.
[[ $- == *p* && $EUID == 0 ]] || { echo "Run the packaged drive password command through sudo." >&2; exit 1; }
set +x +v +a
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
unset new_password current_password
umask 077

fail() { echo "$*" >&2; exit 1; }
state_dir=/var/lib/monarch-drive-password
[[ $# == 1 && $1 == /dev/* && -b $1 ]] || fail "Expected a LUKS block device."
drive=$(readlink -f -- "$1")
[[ $drive == /dev/* && -b $drive ]] || fail "Invalid drive."

exec {lock_fd}>/run/monarch-drive-password.lock
flock -n "$lock_fd" || fail "Another drive password change is running."
provisioning=/var/lib/monarch/provisioning
for pending in pending wipe-pending luks-key; do
  [[ ! -e $provisioning/$pending && ! -L $provisioning/$pending ]] || fail "Finish first-boot provisioning before changing a drive password."
done
if [[ -e $provisioning/luks-rekey-state || -L $provisioning/luks-rekey-state ]]; then
  [[ -f $provisioning/luks-rekey-state && ! -L $provisioning/luks-rekey-state ]] &&
    grep -qx 'phase=done' "$provisioning/luks-rekey-state" || fail "Finish the pending provisioning rekey before changing a drive password."
fi

if [[ ! -e $state_dir && ! -L $state_dir ]]; then mkdir -m 700 -- "$state_dir"; fi
[[ -d $state_dir && ! -L $state_dir && $(stat -c %u:%a -- "$state_dir") == 0:700 ]] || fail "Unsafe password journal directory."

crypto() { timeout --foreground 120 cryptsetup "$@"; }
uuid=$(crypto luksUUID "$drive") || fail "Could not read the LUKS UUID."
[[ $uuid =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]] || fail "Invalid LUKS UUID."
journal=$state_dir/$uuid.json
temporary=''
trap '[[ -z $temporary ]] || rm -f -- "$temporary"' EXIT

snapshot() {
  local dump header
  header=$(timeout --foreground 120 /usr/bin/python3 -I /usr/share/monarch/install/drive-password/metadata.py "$drive" "$uuid") || fail "Cannot read reliable LUKS header metadata."
  if [[ $(jq -r .version <<<"$header") == 1 ]]; then
    jq -ceS .slots <<<"$header"
    return
  fi
  dump=$(crypto luksDump --dump-json-metadata "$drive") || fail "Cannot read LUKS2 metadata."
  jq -ceS '.keyslots | select(type == "object" and length > 0 and all(keys[]; test("^([0-9]|[12][0-9]|3[01])$")))' <<<"$dump" || fail "Invalid LUKS2 key slots."
}

write_journal() {
  temporary=$(mktemp "$state_dir/.journal.XXXXXXXX")
  printf '%s\n' "$record" >"$temporary"
  sync -f "$temporary"
  mv -fT -- "$temporary" "$journal"
  temporary=''
  sync -f "$state_dir"
}

check_key() {
  local key=$1 slot=$2 code=0
  crypto open --test-passphrase --token-type passphrase-only --key-slot "$slot" --key-file <(printf '%s' "$key") "$drive" || code=$?
  case $code in
    0 | 2) return "$code" ;;
    *) fail "Could not check passphrase (cryptsetup status $code); no slot will be removed." ;;
  esac
}

read_current() {
  printf 'Current encryption password: ' >/dev/tty
  IFS= read -rs current_password </dev/tty || fail "Password input cancelled."
  printf '\n' >/dev/tty
  [[ -n $current_password ]] || fail "Current password cannot be empty."
}

confirm() {
  local answer
  printf '%s\nType exactly: %s\n> ' "$1" "$2" >/dev/tty
  IFS= read -r answer </dev/tty || fail "Confirmation cancelled."
  [[ $answer == "$2" ]] || fail "Not confirmed; no slot removed."
}

IFS= read -rd '' new_password || true
[[ -n $new_password ]] || fail "Password cannot be empty."
now=$(snapshot)
resuming=false
if [[ -e $journal || -L $journal ]]; then
  [[ -f $journal && ! -L $journal && $(stat -c %u:%a -- "$journal") == 0:600 ]] || fail "Unsafe password journal."
  record=$(cat -- "$journal")
  jq -e --arg uuid "$uuid" '
    type == "object" and (keys == ["base","new","old","phase","target","uuid","version"]) and
    .version == 1 and .uuid == $uuid and
    (.phase == "prepared" or .phase == "verified") and
    (.base | type == "object" and length > 0 and all(keys[]; test("^([0-9]|[12][0-9]|3[01])$"))) and
    (.old | type == "string" and test("^([0-9]|[12][0-9]|3[01])$")) and
    (.target | type == "string" and test("^([0-9]|[12][0-9]|3[01])$")) and
    .old != .target and .base[.old] != null and .base[.target] == null and
    ((.phase == "prepared" and .new == null) or (.phase == "verified" and (.new | type == "object")))
  ' <<<"$record" >/dev/null || fail "Invalid password journal; manual review required."
  resuming=true
  echo "Resuming password change for LUKS UUID $uuid."
else
  read_current
  matches=()
  for slot in $(jq -r 'keys[]' <<<"$now"); do
    if check_key "$current_password" "$slot"; then matches+=("$slot"); fi
    if check_key "$new_password" "$slot"; then fail "The new password already opens a slot. Choose another."; fi
  done
  (( ${#matches[@]} > 0 )) || fail "That current password does not open the drive."
  old=${matches[0]}
  if (( ${#matches[@]} > 1 )); then
    printf 'The current password opens slots: %s\n' "${matches[*]}" >/dev/tty
    printf 'Slot to replace (other copies remain usable): ' >/dev/tty
    IFS= read -r old </dev/tty || fail "Selection cancelled."
    [[ " ${matches[*]} " == *" $old "* && -n $old ]] || fail "Invalid slot selection."
    confirm "Only slot $old will be replaced; the old password will still open the other copies." "REPLACE $old"
  fi
  target=0
  slot_limit=$(jq -r 'if .[keys[0]].type == "luks1" then 8 else 32 end' <<<"$now")
  while jq -e --arg target "$target" 'has($target)' <<<"$now" >/dev/null; do
    target=$((target + 1))
  done
  (( target < slot_limit )) || fail "No free key slot; no password changed."
  record=$(jq -cnS --arg uuid "$uuid" --arg old "$old" --arg target "$target" --argjson base "$now" '{version:1,uuid:$uuid,old:$old,target:$target,base:$base,new:null,phase:"prepared"}')
  write_journal
fi

old=$(jq -r .old <<<"$record")
target=$(jq -r .target <<<"$record")
phase=$(jq -r .phase <<<"$record")

validate_slots() {
  local current_uuid
  current_uuid=$(crypto luksUUID "$drive") || fail "Could not recheck UUID."
  [[ $current_uuid == "$uuid" ]] || fail "Drive UUID changed; no slot removed."
  now=$(snapshot)
  jq -e --argjson now "$now" '
    . as $r | all(.base | to_entries[];
      . as $entry | if $entry.key == $r.old and $r.phase == "verified" and $now[$entry.key] == null
      then true else $now[$entry.key] == $entry.value end) and
    (if .phase == "verified" then $now[.target] == .new else true end)
  ' <<<"$record" >/dev/null || fail "Recorded key slots changed; manual review required. No slot removed."
}

validate_slots
if [[ $phase == "prepared" ]]; then
  if [[ $resuming == true ]]; then read_current; fi
  check_key "$current_password" "$old" || fail "The current password does not open the recorded old slot."
  for slot in $(jq -r 'keys[]' <<<"$now"); do
    [[ $slot == "$target" ]] && continue
    if check_key "$new_password" "$slot"; then fail "The new password already opens another slot; manual review required."; fi
  done
  if jq -e --arg target "$target" 'has($target)' <<<"$now" >/dev/null; then
    check_key "$new_password" "$target" || fail "The new password does not open the added slot; preserve it and review manually."
    confirm "Slot $target appeared after this attempt began. Confirm it holds THIS change, not an independent recovery key. No recovery slot will be removed." "ADOPT $uuid $target"
  else
    validate_slots
    pbkdf=argon2id
    [[ $(jq -r --arg old "$old" '.base[$old].type' <<<"$record") != "luks1" ]] || pbkdf=pbkdf2
    # Explicit allocation avoids guessing which independently enrolled slot is ours.
    crypto luksAddKey --pbkdf "$pbkdf" --iter-time 2000 --key-slot "$target" --key-file <(printf '%s' "$current_password") "$drive" <(printf '%s' "$new_password") || fail "Adding the key failed; journal retained for retry."
  fi
  validate_slots
  check_key "$new_password" "$target" || fail "New slot verification failed; old slot retained."
  record=$(jq -cS --argjson now "$now" '.new = $now[.target] | .phase = "verified"' <<<"$record")
  write_journal
fi

validate_slots
check_key "$new_password" "$target" || fail "The new password does not open the recorded new slot."
if jq -e --arg old "$old" 'has($old)' <<<"$now" >/dev/null; then
  if [[ ! ${current_password+x} ]]; then read_current; fi
  check_key "$current_password" "$old" || fail "Old slot identity cannot be confirmed; no slot removed."
  validate_slots
  check_key "$new_password" "$target" || fail "New slot verification failed; old slot retained."
  crypto luksKillSlot --batch-mode --key-file <(printf '%s' "$new_password") "$drive" "$old" || fail "Old slot removal failed; journal retained."
fi
validate_slots
jq -e --arg old "$old" 'has($old) | not' <<<"$now" >/dev/null || fail "Old slot is still present; journal retained."
check_key "$new_password" "$target" || fail "Final new password verification failed; journal retained."
rm -- "$journal"
sync -f "$state_dir"
echo "Password change complete. Only the selected old slot was retired; all other slots were preserved."
