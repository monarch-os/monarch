set -euo pipefail

if ((EUID == 0)); then
  test_mode=0
  system_root=
  runtime_root=/usr/share/monarch
  trusted_uid=0
  trust_stop=/
  systemctl_command=/usr/bin/systemctl
  unset MONARCH_ROOT_FILE_TEST_ROOT MONARCH_ROOT_FILE_TEST_RUNTIME
else
  test_mode=1
  system_root=${MONARCH_SLEEP_TEST_ROOT:?}
  [[ $system_root == /* && -d $system_root && ! -L $system_root ]] || exit 1
  system_root=$(/usr/bin/realpath -e -- "$system_root")
  runtime_root=${MONARCH_PATH:?}
  runtime_root=$(/usr/bin/realpath -e -- "$runtime_root")
  [[ $runtime_root == "$system_root/"* ]] || exit 1
  trusted_uid=$EUID
  trust_stop=$system_root
  systemctl_command=${MONARCH_SLEEP_TEST_SYSTEMCTL:?}
  systemctl_command=$(/usr/bin/realpath -e -- "$systemctl_command")
  [[ $systemctl_command == "$system_root/"* && -f $systemctl_command && ! -L $systemctl_command ]] || exit 1
  export MONARCH_ROOT_FILE_TEST_ROOT=$system_root
  export MONARCH_ROOT_FILE_TEST_RUNTIME=$runtime_root
fi

source "${BASH_SOURCE[0]%/*}/../helpers/root-file.sh"

if ((test_mode)); then
  monarch_root_file_trusted_source "$systemctl_command" "$trusted_uid" "$trust_stop" || exit 1
fi

sleep_dir="$system_root/usr/lib/systemd/system-sleep"
drop_in="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
state_dir="$system_root/var/lib/monarch/reconcile/system-sleep-ownership"
reload_marker="$state_dir/systemd-reload-needed"

run_privileged() {
  monarch_root_file_run "$test_mode" "$@"
}

trusted_parent() {
  monarch_root_file_trusted_directory "${1%/*}" "$trusted_uid" "$trust_stop"
}

trusted_entry() {
  local path="$1" target uid

  if [[ -L $path ]]; then
    uid=$(/usr/bin/stat -c '%u' -- "$path") || return 1
    ((uid == trusted_uid)) || return 1
    target=$(/usr/bin/realpath -e -- "$path") || return 1
    monarch_root_file_trusted_source "$target" "$trusted_uid" "$trust_stop"
  else
    monarch_root_file_trusted_source "$path" "$trusted_uid" "$trust_stop"
  fi
}

entry_requires_repair() {
  local source="$1" destination="$2" mode="$3" current_mode checksum

  [[ -e $destination || -L $destination ]] || return 1
  if trusted_entry "$destination"; then
    [[ -L $destination ]] && return 1
    if /usr/bin/cmp -s -- "$source" "$destination"; then
      current_mode=$(/usr/bin/stat -c '%a' -- "$destination")
      [[ $current_mode == "${mode#0}" ]] || return 0
    fi
    # Refresh only recognized shipped hooks; administrator versions stay authoritative.
    checksum=$(/usr/bin/sha256sum -- "$destination") || return 1
    case "${destination##*/}:${checksum%% *}" in
      force-igpu:c093a4ab837c8f8337fb668f42fd5fea564d413a2a7d95279eed18e82b9eec2e | \
        force-igpu:6b8d47cd5c21c7bc30c5425919205ebe945db51864cac1cc5d04aeadf8ac40ba | \
        keyboard-backlight:f313a81e47401f0d38b8602e5997f52c5286d5e97f74027564ddd515b3d16511)
        return 0
        ;;
    esac
    return 1
  fi
  return 0
}

prepare_state_dir() {
  local directory mode
  local -a directories=(
    "$system_root/var"
    "$system_root/var/lib"
    "$system_root/var/lib/monarch"
    "$system_root/var/lib/monarch/reconcile"
    "$state_dir"
  )

  for directory in "${directories[@]}"; do
    if [[ -e $directory || -L $directory ]]; then
      monarch_root_file_trusted_directory "$directory" "$trusted_uid" "$trust_stop" || return 1
      continue
    fi
    monarch_root_file_trusted_directory "${directory%/*}" "$trusted_uid" "$trust_stop" || return 1
    mode=0755
    [[ $directory == "$system_root/var/lib/monarch" || $directory == "$system_root/var/lib/monarch/reconcile" ||
      $directory == "$state_dir" ]] && mode=0700
    run_privileged /usr/bin/install -d -m "$mode" -o root -g root -- "$directory" || return 1
    monarch_root_file_trusted_directory "$directory" "$trusted_uid" "$trust_stop" || return 1
  done
}

preserve_entry() {
  local destination="$1" label="$2" backup_dir

  prepare_state_dir || return 1
  backup_dir=$(run_privileged /usr/bin/mktemp -d -- "$state_dir/$label.XXXXXX") || return 1
  if run_privileged /usr/bin/cp -a --no-dereference -T -- "$destination" "$backup_dir/original"; then
    echo "Preserved previous sleep configuration from $destination at $backup_dir/original" >&2
    return 0
  fi
  run_privileged /usr/bin/rm -rf -- "$backup_dir"
  return 1
}

repair_entry() {
  local asset="$1" source="$2" destination="$3" mode="$4" label="$5"

  [[ -e $destination || -L $destination ]] || return 0
  trusted_parent "$destination" || {
    echo "Unsafe parent for $destination" >&2
    return 1
  }
  entry_requires_repair "$source" "$destination" "$mode" || return 0
  if [[ ! -f $destination || -L $destination ]] ||
    ! /usr/bin/cmp -s -- "$source" "$destination"; then
    preserve_entry "$destination" "$label" || return 1
  fi
  monarch_install_root_file "$asset"
}

repair_entry keyboard-backlight "$runtime_root/default/systemd/system-sleep/keyboard-backlight" \
  "$sleep_dir/keyboard-backlight" 0755 keyboard-backlight
repair_entry force-igpu "$runtime_root/default/systemd/system-sleep/force-igpu" \
  "$sleep_dir/force-igpu" 0755 force-igpu

if [[ -e $drop_in || -L $drop_in ]]; then
  trusted_parent "$drop_in" || {
    echo "Unsafe parent for $drop_in" >&2
    exit 1
  }
fi
if entry_requires_repair "$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf" \
  "$drop_in" 0644; then
  prepare_state_dir
  run_privileged /usr/bin/install -m 0644 -o root -g root /dev/null "$reload_marker"
  repair_entry delay-start "$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf" \
    "$drop_in" 0644 delay-start.conf
fi

if [[ -e $reload_marker || -L $reload_marker ]]; then
  prepare_state_dir
  run_privileged "$systemctl_command" daemon-reload
  run_privileged /usr/bin/rm -f -- "$reload_marker"
fi
