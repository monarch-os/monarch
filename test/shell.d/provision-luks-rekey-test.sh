#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'command rm -rf -- "$test_tmp"' EXIT
sed -e "s|/run/monarch-drive-password.lock|$test_tmp/drive.lock|g" \
  -e "s|/var/lib/monarch-drive-password/|$test_tmp/manual/|g" \
  "$ROOT/install/provisioning/luks-rekey.sh" >"$test_tmp/helper.sh"
source "$test_tmp/helper.sh"
mkdir "$test_tmp/bin"
cat >"$test_tmp/bin/cryptsetup" <<'EOF'
#!/bin/bash
if [[ $1 == slow ]]; then sleep 5; exit 2; fi
[[ $1 == fd && $(cat "$2") == fixture-descriptor-secret ]]
EOF
chmod +x "$test_tmp/bin/cryptsetup"
sed 's/120s/0.1s/g' "$test_tmp/helper.sh" >"$test_tmp/timed-helper.sh"
if PATH="$test_tmp/bin:$PATH" timeout 2s bash -c 'source "$1"; rekey_cryptsetup slow' _ "$test_tmp/timed-helper.sh" >"$test_tmp/timed-output" 2>&1; then
  echo 'FAIL: blocking cryptsetup accepted' >&2; exit 1
else
  [[ $? == 124 ]] && grep -q 'timed out' "$test_tmp/timed-output" || exit 1
fi
PATH="$test_tmp/bin:$PATH" bash -c 'source "$1"; rekey_cryptsetup fd <(printf "%s" fixture-descriptor-secret)' _ "$test_tmp/helper.sh"
echo 'PASS: real timeout terminates a blocking subprocess and preserves descriptor transport'
eval "$(declare -f rekey_verify_boot | sed '1s/rekey_verify_boot/rekey_fixture_verify_boot/')"
eval "$(declare -f rekey_private_path | sed '1s/rekey_private_path/rekey_fixture_private_path/')"
rekey_private_path() {
  # Only the fixture ancestor substitutes for the installed root-owned /var/lib.
  [[ $1 == /tmp ]] || rekey_fixture_private_path "$@"
}

fail() { echo "FAIL: $*" >&2; exit 1; }
event() {
  local n
  n=$(<"$fixture/count"); n=$((n + 1))
  printf '%s\n' "$n" >"$fixture/count"
  printf '%s\n' "$*" >>"$fixture/events"
  if [[ $n == "${kill_at:-0}" ]]; then kill -KILL "$BASHPID"; fi
  if [[ $n == "${interrupt_at:-0}" ]]; then return 71; fi
}
stat() {
  local result
  result=$(command stat "$@") || return
  case $2 in
    '%u %a') printf '0 %s\n' "${result#* }" ;;
    '%u:%a:%h') printf '0:%s\n' "${result#*:}" ;;
    *) printf '%s\n' "$result" ;;
  esac
}
timeout() {
  [[ $1 == --kill-after=5s && $2 == 120s ]] || return 96
  shift 2
  if [[ ${timeout_operation:-} == "$2" ]]; then return 124; fi
  "$@"
}
sync() { event sync; }
mv() { event before-mv && command mv "$@" && event after-mv; }
rm() { event before-rm && command rm "$@" && event after-rm; }
rekey_keyboard() { printf '%064d\n' "${layout_version:-1}"; }
rekey_unlock_present() { [[ -e $fixture/unlock ]]; }
rekey_build_boot() {
  event before-build || return
  [[ ${build_fail:-0} == 0 ]] || return 1
  command rm -f "$fixture/unlock"
  printf '%s\n' "${layout_version:-1}" >"$fixture/built"
  event after-build
}
rekey_verify_boot() {
  event verify-boot || return
  [[ ${verify_fail:-0} == 0 && ! -e $fixture/unlock && -f $fixture/built &&
    $(<"$fixture/built") == "${layout_version:-1}" ]]
}
cryptsetup() {
  local op=$1 slot= key= new= argument secret status=0
  shift
  ! command env | grep -qF 'fixture-owner-key' || return 93
  # Record only argv, never the content consumed through descriptors.
  printf '%s ' "$op" "$@" >>"$fixture/argv"; printf '\n' >>"$fixture/argv"
  event "before-$op" || return
  case $op in
    luksUUID) printf '01234567-89ab-cdef-0123-456789abcdef\n' ;;
    luksDump)
      [[ ${dump_fail:-0} == 0 ]] || return 1
      printf 'Version: %s\nKeyslots:\n' "${luks_version:-2}"
      for argument in "$fixture"/slot-*; do
        [[ -f $argument ]] || continue
        slot=${argument##*slot-}
        if [[ ${luks_version:-2} == 1 ]]; then printf 'Key Slot %s: ENABLED\n' "$slot"
        else printf '  %s: luks2\n' "$slot"; fi
      done
      printf 'Tokens:\n  17: luks2-keyring\n'
      ;;
    open|luksAddKey|luksKillSlot)
      local -a positional=()
      local token=0 external=0
      while (( $# )); do
        case $1 in
          --key-slot) slot=$2; shift 2 ;;
          --key-file) key=$2; shift 2 ;;
          --token-type) [[ $2 == passphrase-only ]] || return 90; token=1; shift 2 ;;
          --disable-external-tokens) external=1; shift ;;
          --*) shift ;;
          -q) shift ;;
          *) positional+=("$1"); shift ;;
        esac
      done
      [[ -n $key ]] || return 91
      secret=$(cat "$key") || return 1
      [[ ${probe_error:-0} == 0 || $op != open ]] || return 4
      case $op in
        open)
          (( token && external )) || return 92
          [[ -f $fixture/slot-$slot && $(<"$fixture/slot-$slot") == "$secret" ]] || status=2
          ;;
        luksAddKey)
          [[ ${add_fail:-0} == 0 && -n $slot && ! -e $fixture/slot-$slot ]] || return 1
          [[ $secret == "$(<"$fixture/staged-original")" ]] || return 2
          cat "${positional[1]}" >"$fixture/slot-$slot"
          ;;
        luksKillSlot)
          [[ ${kill_fail:-0} == 0 ]] || return 1
          [[ $secret == "$(<"$fixture/slot-1")" ]] || return 2
          command rm -f "$fixture/slot-${positional[1]}"
          ;;
      esac
      ;;
    *) return 99 ;;
  esac
  event "after-$op" || return
  return "$status"
}
new_fixture() {
  fixture="$test_tmp/$1"
  mkdir -p "$fixture/state"
  chmod 700 "$test_tmp" "$fixture" "$fixture/state"
  PROVISIONING_DIR="$fixture/state"
  printf 'fixture-temporary-key' >"$PROVISIONING_DIR/luks-key"
  chmod 600 "$PROVISIONING_DIR/luks-key"
  cp "$PROVISIONING_DIR/luks-key" "$fixture/slot-0"
  cp "$PROVISIONING_DIR/luks-key" "$fixture/staged-original"
  printf 'fixture-seller-key' >"$fixture/slot-3"
  printf 'fixture-owner-key' >"$fixture/owner-input"
  password=$(<"$fixture/owner-input")
  touch "$fixture/unlock" "$fixture/events" "$fixture/argv"
  echo 0 >"$fixture/count"
  interrupt_at=0 kill_at=0 build_fail=0 verify_fail=0 add_fail=0 kill_fail=0 probe_error=0 dump_fail=0
  layout_version=1 luks_version=2
}
run_rekey() { (luks_rekey /dev/fixture) >"$fixture/output" 2>&1; }
assert_done() {
  [[ -f $fixture/slot-1 && ! -e $fixture/slot-0 && ! -e $fixture/slot-3 &&
    ! -e $PROVISIONING_DIR/luks-key ]] || fail 'sole owner or temporary-key cleanup'
  grep -qx 'phase=done' "$PROVISIONING_DIR/luks-rekey-state" || fail 'done journal'
  [[ $(command stat -c %a "$PROVISIONING_DIR/luks-rekey-state") == 600 ]] || fail 'journal mode'
  ! grep -qF 'fixture-owner-key' "$fixture/argv" "$fixture/output" "$PROVISIONING_DIR/luks-rekey-state" || fail 'secret escaped transport'
  ! grep -qF 'fixture-temporary-key' "$fixture/argv" "$fixture/output" "$PROVISIONING_DIR/luks-rekey-state" || fail 'temporary secret escaped'
}

new_fixture baseline
run_rekey || { cat "$fixture/output" >&2; fail baseline; }
assert_done
total=$(<"$fixture/count")
run_rekey || fail 'done replay without staged key'
password=wrong
if run_rekey; then fail 'wrong password accepted after completion'; fi
echo 'PASS: completion, replay, token-free slot proof, secret transport'

new_fixture high-slot
mv "$fixture/slot-3" "$fixture/slot-5"
run_rekey || fail 'LUKS2 slot five rejected by a lexicographic slot limit'
assert_done
[[ ! -e $fixture/slot-5 ]] || fail 'slot five survived retirement'
echo 'PASS: LUKS2 single-digit slot numbers are bounded numerically'

for operation in luksUUID luksDump open luksAddKey luksKillSlot; do
  new_fixture "timeout-$operation"
  timeout_operation=$operation
  if run_rekey; then fail "timeout accepted: $operation"; fi
  [[ -f $PROVISIONING_DIR/luks-key && -f $fixture/slot-0 ]] || fail 'timeout destroyed staged recovery'
  ! grep -q 'after-luksKillSlot' "$fixture/events" || fail 'revocation continued after timeout'
  timeout_operation=
  run_rekey || fail "timeout retry: $operation"
  assert_done
done
echo 'PASS: bounded cryptsetup timeouts fail closed and retain resumable state'

# Interrupt before and after every mocked disk operation, fsync and publication.
for ((point = 1; point <= total; point++)); do
  new_fixture "interrupt-$point"
  interrupt_at=$point
  if run_rekey; then fail "injection $point did not fail"; fi
  [[ -e $fixture/slot-0 || -e $fixture/slot-1 ]] || fail "no usable key at $point"
  if [[ ! -e $fixture/slot-0 ]]; then
    [[ -f $fixture/built && ! -e $fixture/unlock ]] || fail "revocation before boot at $point"
  fi
  interrupt_at=0
  run_rekey || { cat "$fixture/output" >&2; fail "resume $point"; }
  assert_done
done
echo "PASS: $total failure boundaries resume, including after staged-slot/key deletion"

for ((point = 1; point <= total; point++)); do
  new_fixture "kill-$point"
  kill_at=$point
  if run_rekey; then fail "SIGKILL injection $point did not fail"; fi
  kill_at=0
  run_rekey || fail "SIGKILL resume $point"
  assert_done
done
echo "PASS: $total SIGKILL boundaries resume without trap-based recovery"

for error in build_fail verify_fail add_fail kill_fail probe_error dump_fail; do
  new_fixture "$error"
  declare "$error=1"
  if run_rekey; then fail "$error accepted"; fi
  [[ -e $PROVISIONING_DIR/luks-key ]] || fail "$error removed staged key"
  declare "$error=0"
  run_rekey || fail "$error retry"
  assert_done
done
echo 'PASS: cryptsetup, rebuild and artifact-verification errors retain recoverability'

for content in 'phase=unknown' 'version=1' 'phase=staged\nphase=owner' 'garbage' ''; do
  new_fixture "corrupt-$RANDOM"
  printf '%b\n' "$content" >"$PROVISIONING_DIR/luks-rekey-state"
  chmod 600 "$PROVISIONING_DIR/luks-rekey-state"
  if run_rekey; then fail 'corrupt journal accepted'; fi
  [[ -f $fixture/slot-0 && ! -e $fixture/slot-1 ]] || fail 'corrupt journal changed slots'
done
new_fixture uuid
build_fail=1
run_rekey && fail 'build unexpectedly passed'
sed -i 's/01234567-89ab-cdef-0123-456789abcdef/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/' "$PROVISIONING_DIR/luks-rekey-state"
build_fail=0
if run_rekey; then fail 'foreign UUID accepted'; fi
echo 'PASS: incomplete, duplicate, unknown and foreign-UUID journals fail closed'

for unsafe in journal-mode journal-symlink key-mode key-symlink parent-mode; do
  new_fixture "$unsafe"
  case $unsafe in
    journal-mode) touch "$PROVISIONING_DIR/luks-rekey-state"; chmod 644 "$PROVISIONING_DIR/luks-rekey-state" ;;
    journal-symlink) ln -s "$fixture/staged-original" "$PROVISIONING_DIR/luks-rekey-state" ;;
    key-mode) chmod 644 "$PROVISIONING_DIR/luks-key" ;;
    key-symlink) command rm "$PROVISIONING_DIR/luks-key"; ln -s "$fixture/staged-original" "$PROVISIONING_DIR/luks-key" ;;
    parent-mode) chmod 777 "$PROVISIONING_DIR" ;;
  esac
  if run_rekey; then fail "unsafe path accepted: $unsafe"; fi
  [[ -f $fixture/slot-0 && ! -e $fixture/slot-1 ]] || fail "$unsafe changed slots"
done
echo 'PASS: root-only modes and symlink rejection before disk mutation'

new_fixture changed-password
build_fail=1
run_rekey && fail 'build unexpectedly passed'
build_fail=0 password=wrong
if run_rekey; then fail 'owner slot silently changed'; fi
[[ -e $fixture/slot-0 ]] || fail 'wrong owner revoked staged slot'
password=$(<"$fixture/owner-input")
run_rekey || fail 'original password retry'
layout_version=2
run_rekey || fail 'keyboard rebuild after completion'
[[ $(<"$fixture/built") == 2 ]] || fail 'keyboard not rebuilt'
printf 'fixture-independent-key' >"$fixture/slot-4"
if run_rekey; then fail 'done journal deleted a newly added recovery slot'; fi
[[ -f $fixture/slot-4 ]] || fail 'post-completion slot deleted'
echo 'PASS: pinned owner password, keyboard rebuild, done-state independent slot refusal'

new_fixture luks1
luks_version=1
run_rekey || fail 'LUKS1'
assert_done
new_fixture duplicate
password=$(<"$fixture/staged-original")
if run_rekey; then fail 'temporary password accepted as owner'; fi
[[ ! -f $fixture/slot-1 && -f $fixture/slot-0 ]] || fail 'temporary password changed slots'
echo 'PASS: LUKS1 parser and duplicate temporary password rejection'

new_fixture locked
exec {held}>"$PROVISIONING_DIR/luks-rekey.lock"
flock "$held"
if run_rekey; then fail 'concurrent invocation accepted'; fi
[[ ! -e $fixture/slot-1 ]] || fail 'concurrent invocation mutated disk'
exec {held}>&-
run_rekey || fail 'retry after lock release'
echo 'PASS: real flock contention serializes invocations'

new_fixture trace
export password
(set -x; luks_rekey /dev/fixture) >"$fixture/output" 2>&1 || fail trace
export -n password
assert_done
echo 'PASS: inherited xtrace disabled before handling secrets'

if bash "$ROOT/bin/monarch-provision-owner" -p >"$test_tmp/decoy" 2>&1; then fail 'ordinary Bash with decoy -p accepted'; fi
grep -q 'launch the packaged' "$test_tmp/decoy" || fail 'privileged Bash guard'
echo 'PASS: privileged entrypoint rejects ordinary Bash decoy'

new_fixture boot-artifacts
rekey_keyboard_prepare() { :; }
rekey_verify_keyboard() { cmp /etc/vconsole.conf "$1/etc/vconsole.conf"; }
mkdir -p "$fixture/esp/EFI/Linux"
printf 'fixture-uki' >"$fixture/esp/EFI/Linux/monarch_fixture.efi"
printf 'KEYMAP=fr\n' >"$fixture/vconsole.conf"
machine=0123456789abcdef0123456789abcdef
hash=$(b2sum "$fixture/esp/EFI/Linux/monarch_fixture.efi" | cut -d' ' -f1)
printf '/Monarch\n  comment: machine-id=%s\n  path: boot():/EFI/Linux/monarch_fixture.efi#%s\n' \
  "$machine" "$hash" >"$fixture/esp/limine.conf"
esp_path() { printf '%s\n' "$fixture/esp"; }
cat() {
  if [[ ${1:-} == /etc/machine-id ]]; then printf '%s\n' "$machine"
  else command cat "$@"; fi
}
cmp() {
  if [[ $1 == /etc/vconsole.conf ]]; then command cmp "$fixture/vconsole.conf" "$2"
  else command cmp "$@"; fi
}
mktemp() {
  if [[ ${2:-} == /run/monarch-rekey-boot.* ]]; then command mktemp -d "$fixture/boot.XXXXXX"
  else command mktemp "$@"; fi
}
objcopy() {
  local arg
  [[ ${objcopy_fail:-0} == 0 ]] || return 1
  for arg in "$@"; do
    case $arg in
      .initrd=*) printf 'fixture-initrd' >"${arg#*=}" ;;
      .cmdline=*) printf '%s' "${cmdline:-quiet}" >"${arg#*=}" ;;
    esac
  done
}
lsinitcpio() {
  [[ ${initrd_fail:-0} == 0 ]] || return 1
  if [[ $1 == -x ]]; then
    mkdir -p etc
    if [[ ${stale_keyboard:-0} == 1 ]]; then printf 'KEYMAP=us\n' >etc/vconsole.conf
    else cp "$fixture/vconsole.conf" etc/vconsole.conf; fi
  else
    printf 'etc/vconsole.conf\n'
    [[ ${embedded_key:-0} == 0 ]] || printf 'etc/monarch/provisioning.key\n'
  fi
}
command rm "$fixture/unlock"
rekey_fixture_verify_boot || fail 'valid referenced UKI rejected'
for fault in objcopy_fail initrd_fail stale_keyboard embedded_key; do
  declare "$fault=1"
  if rekey_fixture_verify_boot >/dev/null 2>&1; then fail "artifact fault $fault accepted"; fi
  declare "$fault=0"
done
for cmdline in 'quiet cryptkey=rootfs:/etc/monarch/provisioning.key' \
  'quiet vconsole.keymap=us' 'quiet rd.vconsole.keymap=us' 'quiet disablehooks=keymap' \
  'quiet LANG=unknown' 'quiet XKB_DEFAULT_LAYOUT=ru' 'quiet XCOMPOSEFILE=/another/Compose' 'quiet HOME=/other'; do
  if rekey_fixture_verify_boot; then fail 'unverified unlock/keyboard cmdline accepted'; fi
done
cmdline=quiet
printf 'changed-uki' >>"$fixture/esp/EFI/Linux/monarch_fixture.efi"
if rekey_fixture_verify_boot; then fail 'hash mismatch accepted'; fi
printf '/Foreign\n' >"$fixture/esp/limine.conf"
if rekey_fixture_verify_boot; then fail 'zero local UKI accepted'; fi
echo 'PASS: real artifact verifier rejects bad hashes, zero UKI, extraction errors, embedded key, unlock cmdline and stale keyboard'

eval "$(sed -n '/^apply_keyboard() {/,/^}/p' "$ROOT/bin/monarch-provision-owner")"
LOG_FILE="$fixture/keyboard-log"
tty() { echo /dev/tty1; }
loadkeys() { [[ ${loadkeys_fail:-0} == 0 ]]; }
systemd-firstboot() { [[ ${firstboot_fail:-0} == 0 ]]; }
localectl() {
  if [[ $* == *list-keymaps* ]]; then echo fr
  else [[ ${localectl_fail:-0} == 0 ]]; fi
}
log_step() { printf '%s\n' "$*" >>"$LOG_FILE"; }
apply_keyboard fr || fail 'known keyboard'
firstboot_fail=1
apply_keyboard fr || fail 'localectl persistence fallback'
localectl_fail=1
if apply_keyboard fr; then fail 'failed keyboard persistence accepted'; fi
firstboot_fail=0 localectl_fail=0 loadkeys_fail=1
if apply_keyboard fr; then fail 'failed live keymap accepted'; fi
loadkeys_fail=0
if apply_keyboard unknown; then fail 'unknown keyboard accepted'; fi
echo 'PASS: live and persisted console layouts must both succeed before collecting the password'
