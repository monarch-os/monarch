#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
system_root="$test_tmp/system"
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
export MONARCH_ROOT_FILE_TEST_ROOT="$system_root"
export MONARCH_ROOT_FILE_TEST_RUNTIME="$system_root/usr/share/monarch"
export RESUME_TEST_CALLS="$test_tmp/calls"
export RESUME_TEST_SOURCE='/dev/nvme0n1p2[/@swap]'
export RESUME_TEST_UUID=0f3c5a1e-7d2b-4c8e-9a61-2b7e4d9c1f08
export PATH="$stub_bin:$PATH"
cat >"$stub_bin/findmnt" <<'EOF'
#!/bin/bash
case $2 in
  SOURCE) echo "$RESUME_TEST_SOURCE" ;;
  UUID) echo "$RESUME_TEST_UUID" ;;
  *) exit 1 ;;
esac
EOF
cat >"$stub_bin/btrfs" <<'EOF'
#!/bin/bash
[[ $1 == subvolume ]] && exit 0
[[ $* == inspect-internal\ map-swapfile\ -r\ * ]] || exit 1
echo 4242
EOF
cat >"$stub_bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
echo rebuild >>"$RESUME_TEST_CALLS"
[[ -n ${REMOVE_OPERATION_TEST:-} || -f $MONARCH_ROOT_FILE_TEST_ROOT/var/lib/monarch/hibernation-resume-rebuild ]] || exit 80
case ${RESUME_TEST_RESULT:-ok} in
  fail) exit 42 ;;
  skip) echo 'ERROR: mkinitcpio failed for kernel linux-cachyos, skipping.' ;;
  signal) kill -TERM "$PPID"; exit 1 ;;
esac
EOF
cat >"$stub_bin/limine-entry-tool" <<'EOF'
#!/bin/bash
[[ $1 == --tree ]] || exit 1
echo validate >>"$RESUME_TEST_CALLS"
[[ ${RESUME_TEST_RESULT:-ok} != invalid ]]
EOF
chmod +x "$stub_bin/"*
drop_in="$system_root/etc/limine-entry-tool.d/resume.conf"
limine="$system_root/etc/default/limine"
pending="$system_root/var/lib/monarch/hibernation-resume-rebuild"
hook="$system_root/etc/mkinitcpio.conf.d/monarch_resume.conf"
old='KERNEL_CMDLINE[default]+=" resume=/dev/nvme1n1p2 resume_offset=4242"'
expected="KERNEL_CMDLINE[default]+=\" resume=UUID=$RESUME_TEST_UUID resume_offset=4242\""
manual='KERNEL_CMDLINE[default]+=" quiet splash my_option=1 resume=/dev/custom resume_offset=12"'

machine() {
  rm -rf -- "$system_root"
  mkdir -p "$system_root/etc/limine-entry-tool.d" "$system_root/etc/default" \
    "$system_root/etc/mkinitcpio.conf.d" "$system_root/var/lib" \
    "$system_root/swap" "$MONARCH_ROOT_FILE_TEST_RUNTIME"
  : >"$system_root/swap/swapfile"
  : >"$system_root/etc/fstab"
  : >"$RESUME_TEST_CALLS"
  printf 'HOOKS+=(resume)\n' >"$hook"
  printf '%s\n' "${1:-$old}" >"$drop_in"
  printf '%s\n' '# administrator settings' "$manual" "${1:-$old}" >"$limine"
}
reconcile() {
  bash "$ROOT/install/reconcile/hibernation-resume.sh" "$@"
}

machine
rm "$drop_in" "$hook"
mkdir -p "$system_root/sys/power"
: >"$system_root/sys/power/image_size"
printf 'deep\n' >"$system_root/sys/power/mem_sleep"
printf '%s none swap defaults,pri=0 0 0\n' "$system_root/swap/swapfile" >"$system_root/etc/fstab"
printf 'source "%s/install/helpers/root-file.sh"\nmonarch_install_root_file() { return 0; }\n' "$ROOT" >"$test_tmp/entry-helpers.sh"
sed -e 's/^unset MONARCH_ROOT_FILE_TEST_ROOT MONARCH_ROOT_FILE_TEST_RUNTIME$/:/' \
  -e "s|/usr/share/monarch/install/helpers/root-file.sh|$test_tmp/entry-helpers.sh|g" \
  -e "s|/usr/share/monarch/install/helpers/hibernation-lock.sh|$ROOT/install/helpers/hibernation-lock.sh|g" \
  -e "s|/usr/share/monarch/install/reconcile/hibernation-resume.sh|$ROOT/install/reconcile/hibernation-resume.sh|g" \
  -e "s|/sys/power/|$system_root/sys/power/|g" \
  -e "s|/etc/mkinitcpio.conf.d|$system_root/etc/mkinitcpio.conf.d|g" \
  -e "s|/etc/limine-entry-tool.d|$system_root/etc/limine-entry-tool.d|g" \
  -e "s|/etc/default/limine|$limine|g" \
  -e "s|/etc/fstab|$system_root/etc/fstab|g" \
  -e "s|/swap/swapfile|$system_root/swap/swapfile|g" \
  -e "s|\"/swap\"|\"$system_root/swap\"|g" \
  "$ROOT/bin/monarch-hibernation-setup" >"$test_tmp/setup"
cat >"$stub_bin/sudo" <<'EOF'
#!/bin/bash
[[ -z ${REMOVE_TEST_CALLS:-} ]] || echo "sudo $*" >>"$REMOVE_TEST_CALLS"
if [[ -n ${REMOVE_OPERATION_TEST:-} ]]; then
  case $1 in
    swapoff)
      [[ $2 == "$MONARCH_ROOT_FILE_TEST_ROOT/swap/swapfile" ]] || exit 96
      exit "${REMOVE_SWAPOFF_STATUS:-0}"
      ;;
    rm | cp)
      for argument in "${@:2}"; do
        [[ $argument == -* || $argument == "$MONARCH_ROOT_FILE_TEST_ROOT/"* ]] || exit 97
      done
      exec "/usr/bin/$1" "${@:2}"
      ;;
    sed)
      [[ ${!#} == "$MONARCH_ROOT_FILE_TEST_ROOT/etc/fstab" ]] || exit 98
      exec /usr/bin/sed "${@:2}"
      ;;
    btrfs)
      [[ $2 == subvolume && ( $3 == show || $3 == delete ) && $4 == "$MONARCH_ROOT_FILE_TEST_ROOT/swap" ]] || exit 99
      exit 0
      ;;
    limine-mkinitcpio) exec "$@" ;;
    *) exit 100 ;;
  esac
fi
case $1 in
  bash | btrfs | swapon | swaplabel) exec "$@" ;;
  mkdir | tee)
    for argument in "${@:2}"; do
      [[ $argument == -* || $argument == "$MONARCH_ROOT_FILE_TEST_ROOT/"* ]] || exit 90
    done
    exec "$@"
    ;;
  *) exit 91 ;;
esac
EOF
cat >"$stub_bin/swapon" <<'EOF'
#!/bin/bash
[[ $1 != --show ]] || echo "$MONARCH_ROOT_FILE_TEST_ROOT/swap/swapfile"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/swaplabel"
chmod +x "$stub_bin/sudo" "$stub_bin/swapon" "$stub_bin/swaplabel"
bash "$test_tmp/setup" --force --no-rebuild
[[ $(<"$drop_in") == "$expected" && -f $pending && ! -s $RESUME_TEST_CALLS ]] || fail 'public setup still emits a volatile NVMe resume device'
bash "$test_tmp/setup" --force
[[ ! -e $pending && $(<"$RESUME_TEST_CALLS") == $'rebuild\nvalidate' ]] || fail 'public rerun did not finish the deferred rebuild'
pass 'public setup uses UUID on first setup and retries a deferred rebuild on rerun'

machine
printf '%s\n' 'KERNEL_CMDLINE[default]+="resume=/dev/nvme0n1p2 resume_offset=4242"' >>"$limine"
reconcile
[[ $(<"$drop_in") == "$expected" && ! -e $pending ]] || fail 'NVMe rename failed'
[[ $(grep -cxF "$expected" "$limine") == 2 ]] || fail 'priority duplicates were not repaired'
grep -qxF "$manual" "$limine" || fail 'administrator cmdline lost'
[[ $(<"$RESUME_TEST_CALLS") == $'rebuild\nvalidate' ]] || fail 'rebuild validation missing'
: >"$RESUME_TEST_CALLS"
export RESUME_TEST_SOURCE='/dev/nvme1n1p2[/@swap]'
reconcile
[[ ! -s $RESUME_TEST_CALLS ]] || fail 'NVMe probe order broke idempotence'
pass 'two NVMe kernel names converge to the filesystem UUID and priority copies preserve user options'

machine
rm "$drop_in" "$hook"
printf '%s\n' "$manual" >"$limine"
reconcile --setup --no-rebuild
[[ $(<"$drop_in") == "$expected" && -f $hook && -f $pending ]] || fail 'fresh NVMe setup did not use UUID'
grep -qxF "$manual" "$limine" || fail 'fresh setup lost user cmdline'
pass 'fresh unencrypted setup publishes UUID and deferred intent'

machine 'KERNEL_CMDLINE[default]+="resume=/dev/mapper/root resume_offset=4242"'
before=$(sha256sum "$drop_in" "$limine")
export RESUME_TEST_SOURCE='/dev/mapper/root[/@swap]'
reconcile
[[ $(sha256sum "$drop_in" "$limine") == "$before" && ! -s $RESUME_TEST_CALLS ]] || fail 'mapper state changed'
machine
rm "$drop_in" "$hook"
printf '%s\n' "$manual" >"$limine"
reconcile --setup --no-rebuild
grep -qF 'resume=/dev/mapper/root ' "$drop_in" || fail 'fresh LUKS setup lost mapper'
[[ -f $hook && -f $pending && ! -s $RESUME_TEST_CALLS ]] || fail 'deferred fresh setup missing intent'
pass 'existing and fresh encrypted setup retain the mapper name'
export RESUME_TEST_SOURCE='/dev/nvme0n1p2[/@swap]'

machine 'KERNEL_CMDLINE[default]+=" resume=/dev/nvme1n1p2 resume_offset="'
reconcile
[[ $(<"$drop_in") == "$expected" ]] || fail 'empty offset not repaired before UUID rename'
grep -qxF "$expected" "$limine" || fail 'empty offset main copy not repaired'
pass 'empty offsets are repaired in both generated locations'

for result in fail skip signal invalid; do
  machine
  export RESUME_TEST_RESULT=$result
  if (reconcile) >"$test_tmp/output" 2>&1; then
    fail "incomplete rebuild accepted: $result"
  fi
  [[ -f $pending && $(<"$drop_in") == "$expected" ]] || fail "retry intent lost: $result"
  export RESUME_TEST_RESULT=ok
  : >"$RESUME_TEST_CALLS"
  reconcile
  [[ ! -e $pending && $(<"$RESUME_TEST_CALLS") == $'rebuild\nvalidate' ]] || fail "retry failed: $result"
  : >"$RESUME_TEST_CALLS"
  reconcile
  [[ ! -s $RESUME_TEST_CALLS ]] || fail "retry rebuilt twice: $result"
done
pass 'nonzero, exit-zero skipped kernel, signal and failed tree validation all retain retry intent'

machine
reconcile --no-rebuild
[[ -f $pending && ! -s $RESUME_TEST_CALLS ]] || fail 'no-rebuild discarded pending state'
# Simulate interruption after the drop-in rename but before the main-file write.
printf '%s\n' "$manual" "$old" >"$limine"
printf '%s\n' 'KERNEL_CMDLINE[default]+="resume=/dev/nvme1n1p2 resume_offset="' >>"$limine"
reconcile --no-rebuild
grep -qxF "$expected" "$limine" || fail 'partial publication did not repair main file'
[[ $(grep -cxF "$expected" "$limine") == 2 ]] || fail 'partial empty-offset copy not repaired'
reconcile
[[ ! -e $pending ]] || fail 'deferred rebuild was not completed'
pass 'no-rebuild retains durable intent and retry repairs a partially published pair'

mapper_empty='KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset="'
mapper_fixed='KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=4242"'
machine "$mapper_empty"
export RESUME_TEST_SOURCE='/dev/mapper/root[/@swap]'
reconcile --no-rebuild
other_mapper='KERNEL_CMDLINE[default]+=" resume=/dev/mapper/other resume_offset="'
printf '%s\n' "$manual" "$mapper_empty" "$other_mapper" >"$limine"
reconcile
grep -qxF "$mapper_fixed" "$limine" || fail 'interrupted mapper repair left the main resume offset empty'
grep -qxF "$other_mapper" "$limine" || fail 'mapper retry modified another mapper'
grep -qxF "$manual" "$limine" || fail 'mapper retry lost administrator settings'
[[ ! -e $pending ]] || fail 'mapper retry did not complete'
export RESUME_TEST_SOURCE='/dev/nvme0n1p2[/@swap]'
pass 'interrupted mapper resume repair updates the old main-file copy before acknowledging the rebuild'

machine
reconcile --no-rebuild
rm "$hook" "$drop_in"
printf '%s\n' "$manual" >"$limine"
reconcile
[[ -f $hook && $(<"$drop_in") == "$expected" && ! -e $pending ]] || fail 'interrupted initial publication could not resume'
grep -qxF "$manual" "$limine" || fail 'initial publication retry lost user settings'
pass 'durable intent also resumes interruption before the first hook/drop-in publication'

for custom in "$manual" $'KERNEL_CMDLINE[default]+=" resume=/dev/nvme0n1p2\tresume_offset=4242"'; do
  machine "$custom"
  before=$(sha256sum "$drop_in" "$limine")
  reconcile
  [[ $(sha256sum "$drop_in" "$limine") == "$before" && ! -s $RESUME_TEST_CALLS && ! -e $pending ]] || fail 'manual drop-in was adopted'
done
machine
reconcile --no-rebuild
printf '%s\n' "$manual" >"$drop_in"
if reconcile; then fail 'pending custom edit accepted'; fi
[[ -f $pending ]] || fail 'custom edit cleared retry intent'
pass 'customized drop-ins are preserved and cannot silently complete a pending rebuild'

machine
export RESUME_TEST_UUID=''
if reconcile; then fail 'missing UUID fell back to volatile kernel name'; fi
[[ $(<"$drop_in") == "$old" && ! -s $RESUME_TEST_CALLS ]] || fail 'missing UUID changed owned state'
export RESUME_TEST_UUID=0f3c5a1e-7d2b-4c8e-9a61-2b7e4d9c1f08
for target in "$drop_in" "$limine" "$pending" "$system_root/var/lib/monarch/hibernation-resume.lock"; do
  machine
  mkdir -p "${target%/*}"
  rm -f -- "$target"
  printf 'untouched\n' >"$test_tmp/victim"
  ln -s "$test_tmp/victim" "$target"
  if reconcile; then fail "symlink trusted: $target"; fi
  [[ $(<"$test_tmp/victim") == untouched && ! -s $RESUME_TEST_CALLS ]] || fail 'symlink redirected publication'
done
machine
chmod 0777 "${drop_in%/*}"
if reconcile; then fail 'writable parent trusted'; fi
[[ $(<"$drop_in") == "$old" ]] || fail 'unsafe parent changed configuration'
pass 'missing UUID, symlinks and writable system parents fail closed without rebuilding'

machine
exec {unrelated_fd}>"$test_tmp/unrelated-lock"
for inherited in invalid "$unrelated_fd"; do
  if reconcile --lock-fd "$inherited"; then fail 'unrelated inherited descriptor accepted'; fi
  [[ $(<"$drop_in") == "$old" && ! -e $pending && ! -s $RESUME_TEST_CALLS ]] || fail 'invalid inherited lock changed configuration'
done
exec {unrelated_fd}>&-
pass 'inherited lock descriptors must reference the trusted shared lock inode'

sed -e 's/^unset MONARCH_ROOT_FILE_TEST_ROOT MONARCH_ROOT_FILE_TEST_RUNTIME$/:/' \
  -e "s|/usr/share/monarch/install/helpers/root-file.sh|$ROOT/install/helpers/root-file.sh|g" \
  -e "s|/usr/share/monarch/install/helpers/hibernation-lock.sh|$ROOT/install/helpers/hibernation-lock.sh|g" \
  "$ROOT/bin/monarch-hibernation-remove" >"$test_tmp/remove"
export REMOVE_TEST_CALLS="$test_tmp/remove-calls"
cat >"$stub_bin/gum" <<'EOF'
#!/bin/bash
echo confirm >>"$REMOVE_TEST_CALLS"
[[ -z ${SETUP_REBOOT_TEST:-} && -z ${REMOVE_OPERATION_TEST:-} ]] || exit 0
if [[ -n ${REMOVE_TEST_PROMPT_READY:-} ]]; then
  echo prompt >"$REMOVE_TEST_PROMPT_READY"
  read -r answer <"$REMOVE_TEST_PROMPT_CONTINUE"
fi
exit 1
EOF
cat >"$stub_bin/flock" <<'EOF'
#!/bin/bash
[[ -z ${RESUME_TEST_LOCK_READY:-} ]] || echo waiting >"$RESUME_TEST_LOCK_READY"
exec /usr/bin/flock "$@"
EOF
chmod +x "$stub_bin/gum" "$stub_bin/flock"
remove_hibernation() {
  bash "$test_tmp/remove"
}

for hook_state in present absent; do
  machine
  reconcile --no-rebuild
  [[ $hook_state == present ]] || rm "$hook"
  : >"$REMOVE_TEST_CALLS"
  before=$(sha256sum "$pending" "$system_root/swap/swapfile" "$drop_in" "$limine")
  if remove_hibernation >"$test_tmp/remove-out" 2>&1; then fail "pending removal accepted ($hook_state hook)"; fi
  grep -qF 'Finish hibernation setup/reconciliation' "$test_tmp/remove-out" || fail 'pending removal lacks retry guidance'
  [[ $(sha256sum "$pending" "$system_root/swap/swapfile" "$drop_in" "$limine") == "$before" ]] || fail 'pending removal changed system state'
  [[ ! -s $REMOVE_TEST_CALLS && ! -s $RESUME_TEST_CALLS ]] || fail 'pending removal prompted, disabled swap, removed files or rebuilt'
done
machine
: >"$REMOVE_TEST_CALLS"
remove_hibernation
[[ $(<"$REMOVE_TEST_CALLS") == confirm && -f $hook && -f $system_root/swap/swapfile && ! -s $RESUME_TEST_CALLS ]] || fail 'cancelled removal changed state'
rm "$hook"
: >"$REMOVE_TEST_CALLS"
remove_hibernation >"$test_tmp/remove-out"
grep -qF 'Hibernation is not set up' "$test_tmp/remove-out" || fail 'inactive removal failed'
[[ ! -s $REMOVE_TEST_CALLS && ! -s $RESUME_TEST_CALLS ]] || fail 'inactive removal performed work'
pass 'public removal refuses pending work with or without a hook, and cancellation/inactive state are non-destructive'

machine
printf '%s none swap defaults,pri=0 0 0\n' "$system_root/swap/swapfile" >"$system_root/etc/fstab"
: >"$REMOVE_TEST_CALLS"
before=$(sha256sum "$hook" "$system_root/swap/swapfile" "$system_root/etc/fstab")
if REMOVE_OPERATION_TEST=1 REMOVE_SWAPOFF_STATUS=42 remove_hibernation >"$test_tmp/remove-out" 2>&1; then
  fail 'failed swapoff completed removal'
else
  [[ $? == 42 ]] || fail 'swapoff failure status was lost'
fi
[[ $(sha256sum "$hook" "$system_root/swap/swapfile" "$system_root/etc/fstab") == "$before" ]] || fail 'failed swapoff allowed destructive cleanup'
[[ $(<"$REMOVE_TEST_CALLS") == $'confirm\nsudo swapoff '"$system_root/swap/swapfile" && ! -s $RESUME_TEST_CALLS ]] || fail 'failed swapoff continued with removal operations'
! grep -qxF 'Hibernation removed' "$test_tmp/remove-out" || fail 'failed swapoff reported success'
for result in fail skip signal invalid; do
  machine
  printf '%s none swap defaults,pri=0 0 0\n' "$system_root/swap/swapfile" >"$system_root/etc/fstab"
  : >"$REMOVE_TEST_CALLS"
  if REMOVE_OPERATION_TEST=1 RESUME_TEST_RESULT=$result remove_hibernation >"$test_tmp/remove-out" 2>&1; then
    fail "failed removal rebuild reported success ($result)"
  fi
  [[ $(grep -cx rebuild "$RESUME_TEST_CALLS") == 1 ]] || fail 'removal did not reach the mocked rebuild'
  ! grep -qxF 'Hibernation removed' "$test_tmp/remove-out" || fail 'failed rebuild printed removal success'
  [[ -f $system_root/var/lib/monarch/hibernation-remove-rebuild ]] || fail 'failed removal lost durable intent'
  before=$(sha256sum "$system_root/var/lib/monarch/hibernation-remove-rebuild" "$limine" "$system_root/etc/fstab")
  if reconcile >"$test_tmp/remove-block-reconcile" 2>&1; then fail 'reconciliation recreated pending removal'; fi
  if bash "$test_tmp/setup" --force >"$test_tmp/remove-block-setup" 2>&1; then fail 'setup recreated pending removal'; fi
  [[ $(sha256sum "$system_root/var/lib/monarch/hibernation-remove-rebuild" "$limine" "$system_root/etc/fstab") == "$before" ]] || fail 'setup/reconcile mutated removal intent'
  REMOVE_OPERATION_TEST=1 RESUME_TEST_RESULT=ok remove_hibernation >"$test_tmp/remove-retry-out" 2>&1
  [[ $(grep -cx rebuild "$RESUME_TEST_CALLS") == 2 ]] || fail 'removal retry skipped boot rebuild after hook deletion'
  [[ ! -e $system_root/var/lib/monarch/hibernation-remove-rebuild ]] || fail 'successful removal did not acknowledge intent'
  [[ ! -e $drop_in ]] || fail 'generated resume drop-in survived removal'
  ! grep -qxF "$old" "$limine" || fail 'generated main resume copy survived removal'
  grep -qxF "$manual" "$limine" || fail 'removal lost administrator cmdline'
done
pass 'failed swapoff stops all cleanup; failed or exit-zero skipped rebuilds cannot report removal success'

for target in "$drop_in" "$limine" "$system_root/var/lib/monarch/hibernation-remove-rebuild"; do
  machine
  mkdir -p "${target%/*}"
  rm -f -- "$target"
  printf 'untouched\n' >"$test_tmp/remove-victim"
  ln -s "$test_tmp/remove-victim" "$target"
  : >"$REMOVE_TEST_CALLS"
  if REMOVE_OPERATION_TEST=1 remove_hibernation >"$test_tmp/remove-out" 2>&1; then fail 'removal trusted a symlink'; fi
  [[ $(<"$test_tmp/remove-victim") == untouched && -f $system_root/swap/swapfile && ! -s $REMOVE_TEST_CALLS ]] || fail 'unsafe removal changed state'
done
pass 'removal rejects symlinked state/configuration before confirmation or swap deletion'

machine
mkdir -p "${pending%/*}"
lock="${pending%/*}/hibernation-resume.lock"
exec {held_fd}>"$lock"
/usr/bin/flock "$held_fd"
mkfifo "$test_tmp/lock-ready"
exec {ready_fd}<>"$test_tmp/lock-ready"
: >"$REMOVE_TEST_CALLS"
(
  exec {held_fd}>&-
  RESUME_TEST_LOCK_READY="$test_tmp/lock-ready" remove_hibernation >"$test_tmp/remove-out" 2>&1
) &
remover=$!
read -r -t 10 -u "$ready_fd" event || fail 'removal did not request the shared lock'
printf 'resume rebuild pending\n' >"$pending"
rm "$hook"
/usr/bin/flock -u "$held_fd"
exec {held_fd}>&-
if wait "$remover"; then fail 'waiting removal checked pending before acquiring the lock'; fi
[[ -f $pending && -f $system_root/swap/swapfile && ! -s $REMOVE_TEST_CALLS && ! -s $RESUME_TEST_CALLS ]] || fail 'waiting removal mutated state'
pass 'removal rechecks pending under the shared lock after a concurrent setup publishes intent'

machine
mkfifo "$test_tmp/prompt-ready" "$test_tmp/prompt-continue"
exec {prompt_fd}<>"$test_tmp/prompt-ready"
REMOVE_TEST_PROMPT_READY="$test_tmp/prompt-ready" REMOVE_TEST_PROMPT_CONTINUE="$test_tmp/prompt-continue" remove_hibernation &
remover=$!
read -r -t 10 -u "$prompt_fd" event || fail 'removal did not reach confirmation'
RESUME_TEST_LOCK_READY="$test_tmp/lock-ready" reconcile --no-rebuild &
repairer=$!
read -r -t 10 -u "$ready_fd" event || fail 'reconciliation did not request the shared lock'
[[ ! -e $pending && $(<"$drop_in") == "$old" ]] || fail 'reconciliation published during removal confirmation'
echo cancel >"$test_tmp/prompt-continue"
wait "$remover"
wait "$repairer"
[[ -f $pending && -f $hook && -f $system_root/swap/swapfile ]] || fail 'cancelled removal blocked the later repair'
pass 'removal holds the shared lock through confirmation; cancellation releases it for reconciliation'

machine
rm "$hook" "$drop_in"
printf '%s none swap defaults,pri=0 0 0\n' "$system_root/swap/swapfile" >"$system_root/etc/fstab"
mkdir -p "$system_root/sys/power"
: >"$system_root/sys/power/image_size"
printf 'deep\n' >"$system_root/sys/power/mem_sleep"
# Emulate only the root reboot branch; all privileged/session commands stay mocked.
sed 's/if ((EUID == 0)) \&\&/if true \&\&/' "$test_tmp/setup" >"$test_tmp/setup-root-branch"
cat >"$stub_bin/runuser" <<'EOF'
#!/bin/bash
[[ $1 == -u && $2 == "$(id -un)" && $3 == -- && $4 == env && $5 == "XDG_RUNTIME_DIR=/run/user/$(id -u)" && $6 == /usr/bin/monarch-system-reboot ]] || exit 92
for descriptor in /proc/$$/fd/*; do
  [[ $(readlink "$descriptor") != "$MONARCH_ROOT_FILE_TEST_ROOT/var/lib/monarch/hibernation-resume.lock" ]] || exit 93
done
if /usr/bin/flock -n "$MONARCH_ROOT_FILE_TEST_ROOT/var/lib/monarch/hibernation-resume.lock" true; then exit 94; fi
echo session-reboot >>"$REMOVE_TEST_CALLS"
EOF
printf '#!/bin/bash\nexit 95\n' >"$stub_bin/monarch-system-reboot"
chmod +x "$stub_bin/runuser" "$stub_bin/monarch-system-reboot"
: >"$REMOVE_TEST_CALLS"
SETUP_REBOOT_TEST=1 SUDO_UID=$(id -u) bash "$test_tmp/setup-root-branch"
grep -qxF session-reboot "$REMOVE_TEST_CALLS" || fail 'root setup did not return the reboot request to the caller session'
pass 'setup preserves the caller session for reboot without passing its privileged lock descriptor'
