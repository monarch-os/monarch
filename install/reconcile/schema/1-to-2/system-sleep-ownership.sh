set -euo pipefail

source "$MONARCH_PATH/install/helpers/root-file.sh"

if ((EUID == 0)); then
  system_root=
  trusted_uid=0
  systemctl_command=/usr/bin/systemctl
else
  system_root=${MONARCH_SLEEP_TEST_ROOT:?}
  [[ $system_root == /* && -d $system_root && ! -L $system_root ]] || exit 1
  trusted_uid=$EUID
  systemctl_command=systemctl
fi

sleep_dir="$system_root/usr/lib/systemd/system-sleep"
drop_in="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
state_dir="$system_root/var/lib/monarch/reconcile/system-sleep-ownership"
reload_marker="$state_dir/systemd-reload-needed"

trusted_path() {
  local path="$1" uid mode

  [[ -f $path && ! -L $path ]] || return 1
  uid=$(/usr/bin/stat -c '%u' -- "$path") || return 1
  mode=$(/usr/bin/stat -c '%a' -- "$path") || return 1
  ((uid == trusted_uid && (8#$mode & 8#022) == 0))
}

trusted_parent() {
  local path="${1%/*}" uid mode stop=/
  [[ -n $system_root ]] && stop=$system_root

  while :; do
    [[ -d $path && ! -L $path ]] || return 1
    uid=$(/usr/bin/stat -c '%u' -- "$path") || return 1
    mode=$(/usr/bin/stat -c '%a' -- "$path") || return 1
    ((uid == trusted_uid && (8#$mode & 8#022) == 0)) || return 1
    [[ $path == "$stop" ]] && return 0
    path=${path%/*}
    [[ -n $path ]] || path=/
  done
}

entry_needs_repair() {
  local source="$1" destination="$2" mode="$3" current_mode

  [[ -e $destination || -L $destination ]] || return 1
  if trusted_parent "$destination" && trusted_path "$destination"; then
    if /usr/bin/cmp -s -- "$source" "$destination"; then
      current_mode=$(/usr/bin/stat -c '%a' -- "$destination")
      [[ $current_mode == "${mode#0}" ]] || return 0
    fi
    return 1
  fi
  return 0
}

preserve_entry() {
  local destination="$1" label="$2" backup_dir

  as_root /usr/bin/install -d -m 0700 -o root -g root "$state_dir" || return 1
  backup_dir=$(as_root /usr/bin/mktemp -d -- "$state_dir/$label.XXXXXX") || return 1
  if as_root /usr/bin/cp -a --no-dereference -T -- "$destination" "$backup_dir/original"; then
    echo "Preserved unsafe custom content from $destination at $backup_dir/original" >&2
    return 0
  fi
  as_root /usr/bin/rm -rf -- "$backup_dir"
  return 1
}

repair_entry() {
  local source="$1" destination="$2" mode="$3" label="$4"

  entry_needs_repair "$source" "$destination" "$mode" || return 0
  if [[ ! -f $destination || -L $destination ]] ||
    ! /usr/bin/cmp -s -- "$source" "$destination"; then
    preserve_entry "$destination" "$label" || return 1
  fi
  monarch_install_root_file "$source" "$destination" "$mode"
}

repair_entry "$MONARCH_PATH/default/systemd/system-sleep/keyboard-backlight" \
  "$sleep_dir/keyboard-backlight" 0755 keyboard-backlight
repair_entry "$MONARCH_PATH/default/systemd/system-sleep/force-igpu" \
  "$sleep_dir/force-igpu" 0755 force-igpu

if entry_needs_repair "$MONARCH_PATH/default/systemd/supergfxd.service.d/delay-start.conf" \
  "$drop_in" 0644; then
  as_root /usr/bin/install -Dm0644 -o root -g root /dev/null "$reload_marker"
  repair_entry "$MONARCH_PATH/default/systemd/supergfxd.service.d/delay-start.conf" \
    "$drop_in" 0644 delay-start.conf
fi

if [[ -e $reload_marker || -L $reload_marker ]]; then
  as_root "$systemctl_command" daemon-reload
  as_root /usr/bin/rm -f -- "$reload_marker"
fi
