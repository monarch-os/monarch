set -euo pipefail
umask 077

if ((EUID == 0)); then
  export PATH=/usr/bin:/usr/sbin
fi
source "${BASH_SOURCE[0]%/*}/../helpers/root-file.sh"
source "${BASH_SOURCE[0]%/*}/../helpers/hibernation-lock.sh"
monarch_root_file_context system_root runtime_root trusted_uid stop test_mode
if ((EUID != 0 && ! test_mode)); then
  echo "The hibernation resume repair must run as root" >&2
  exit 1
fi

setup=false
no_rebuild=false
inherited_lock=""
while (($#)); do
  argument=$1
  case $argument in
    --setup) setup=true ;;
    --no-rebuild) no_rebuild=true ;;
    --lock-fd)
      shift
      (($#)) || exit 1
      inherited_lock=$1
      ;;
    *) echo "Unknown hibernation resume argument: $argument" >&2; exit 1 ;;
  esac
  shift
done

hook="$system_root/etc/mkinitcpio.conf.d/monarch_resume.conf"
drop_in="$system_root/etc/limine-entry-tool.d/resume.conf"
limine="$system_root/etc/default/limine"
swap="$system_root/swap/swapfile"
state_dir="$system_root/var/lib/monarch"
pending="$state_dir/hibernation-resume-rebuild"
stages=()
trap 'rm -f -- "${stages[@]}"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ensure_parent() {
  local parent=${1%/*}
  if [[ ! -e $parent && ! -L $parent ]]; then
    monarch_root_file_trusted_directory "${parent%/*}" "$trusted_uid" "$stop"
    install -d -m 0755 -- "$parent"
  fi
  monarch_root_file_trusted_directory "$parent" "$trusted_uid" "$stop"
  if [[ -e $1 || -L $1 ]]; then
    monarch_root_file_trusted_source "$1" "$trusted_uid" "$stop"
  fi
}

stage_file() {
  local destination=$1
  ensure_parent "$destination"
  stage=$(mktemp "${destination%/*}/.${destination##*/}.monarch.XXXXXX")
  stages+=("$stage")
  if [[ -f $destination ]]; then
    cp --preserve=mode,ownership -- "$destination" "$stage"
  else
    chmod 0644 "$stage"
  fi
}

mark_pending() {
  stage_file "$pending"
  printf 'resume rebuild pending\n' >"$stage"
  mv -fT -- "$stage" "$pending"
  # The intent must reach disk before publishing either half of the configuration.
  sync -f "$state_dir"
}

monarch_hibernation_lock "$inherited_lock"
monarch_hibernation_require_no_removal
if [[ -e $pending || -L $pending ]]; then
  monarch_root_file_trusted_source "$pending" "$trusted_uid" "$stop"
  setup=true
fi
if [[ ! -f $hook ]]; then
  if ! $setup; then
    exit 0
  fi
else
  monarch_root_file_trusted_source "$hook" "$trusted_uid" "$stop"
  if [[ $(<"$hook") != 'HOOKS+=(resume)' ]]; then
    [[ ! -e $pending ]] || { echo "Resume hook customized while rebuild is pending" >&2; exit 1; }
    exit 0
  fi
fi

previous=""
offset=""
device=""
# These are the two historical forms emitted by setup, not arbitrary shell code.
pattern='^KERNEL_CMDLINE\[default\]\+=" ?resume=(/dev/[^[:space:]"$`\\]+|UUID=[a-fA-F0-9-]+) resume_offset=([0-9]*)"$'
if [[ -e $drop_in || -L $drop_in ]]; then
  monarch_root_file_trusted_source "$drop_in" "$trusted_uid" "$stop"
  previous=$(<"$drop_in")
  if [[ $previous =~ $pattern ]]; then
    device=${BASH_REMATCH[1]}
    offset=${BASH_REMATCH[2]}
  else
    [[ ! -e $pending ]] || { echo "Resume configuration was customized while a rebuild is pending; review it before retrying" >&2; exit 1; }
    exit 0
  fi
elif ! $setup; then
  [[ ! -e $pending ]] || { echo "Resume configuration missing while a rebuild is pending" >&2; exit 1; }
  exit 0
fi

[[ -f $swap ]] || { echo "Missing hibernation swapfile" >&2; exit 1; }
if [[ -z $device || ( $device == /dev/* && $device != /dev/mapper/* ) ]]; then
  source_device=$(findmnt -no SOURCE -T "$swap")
  source_device=${source_device%%\[*}
  if [[ $source_device == /dev/mapper/* ]]; then
    device=$source_device
  else
    uuid=$(findmnt -no UUID -T "$swap")
    [[ $uuid =~ ^[a-fA-F0-9-]+$ ]] || { echo "Could not identify the swap filesystem UUID" >&2; exit 1; }
    device="UUID=$uuid"
  fi
fi
[[ $device =~ ^(/dev/mapper/[a-zA-Z0-9_+.-]+|UUID=[a-fA-F0-9-]+)$ ]] || exit 1
if [[ -z $offset ]]; then
  offset=$(btrfs inspect-internal map-swapfile -r "$swap")
  [[ $offset =~ ^[0-9]+$ ]] || { echo "Could not determine the resume offset" >&2; exit 1; }
fi
expected="KERNEL_CMDLINE[default]+=\" resume=$device resume_offset=$offset\""
if [[ $previous =~ $pattern && ${BASH_REMATCH[1]} == "$device" && ${BASH_REMATCH[2]} == "$offset" ]]; then
  expected=$previous
fi

stage_file "$drop_in"
drop_stage=$stage
printf '%s\n' "$expected" >"$drop_stage"
stage_file "$limine"
limine_stage=$stage
# Limine's main configuration can contain older, higher-priority copies. Only
# exact generated append-only resume lines with this swap offset belong to us.
while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == "$previous" && -n $previous ]]; then
    printf '%s\n' "$expected"
  elif [[ $line =~ $pattern && ( ${BASH_REMATCH[2]} == "$offset" || -z ${BASH_REMATCH[2]} ) && ( ${BASH_REMATCH[1]} == "$device" || ( ${BASH_REMATCH[1]} == /dev/* && ${BASH_REMATCH[1]} != /dev/mapper/* ) ) ]]; then
    printf '%s\n' "$expected"
  else
    printf '%s\n' "$line"
  fi
done <"$limine" >"$limine_stage"
if [[ -z $previous ]] && ! grep -qxF "$expected" "$limine_stage"; then
  printf '%s\n' "$expected" >>"$limine_stage"
fi

if ! cmp -s "$drop_stage" "$drop_in" || ! cmp -s "$limine_stage" "$limine" || [[ ! -f $hook ]]; then
  mark_pending
  if [[ ! -f $hook ]]; then
    stage_file "$hook"
    printf 'HOOKS+=(resume)\n' >"$stage"
    mv -fT -- "$stage" "$hook"
  fi
  mv -fT -- "$drop_stage" "$drop_in"
  mv -fT -- "$limine_stage" "$limine"
  sync -f "${drop_in%/*}"
  sync -f "${limine%/*}"
fi

[[ -e $pending ]] || exit 0
if $no_rebuild; then
  echo "Resume configuration updated; boot image rebuild remains pending"
  exit 0
fi
stage_file "$pending"
log=$stage
chmod 0600 "$log"
if ! limine-mkinitcpio 2>&1 | tee "$log"; then
  echo "Resume boot image rebuild failed; retry hibernation setup before rebooting" >&2
  exit 1
fi
if grep -q 'mkinitcpio failed for kernel' "$log"; then
  echo "A kernel image was skipped; resume rebuild remains pending" >&2
  exit 1
fi
limine-entry-tool --tree --no-hooks >/dev/null
sync
rm -- "$pending"
sync -f "$state_dir"
