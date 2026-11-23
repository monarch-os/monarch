monarch_hibernation_lock() {
  local inherited=${1:-} lock="$system_root/var/lib/monarch/hibernation-resume.lock" parent
  parent=${lock%/*}
  if [[ ! -e $parent && ! -L $parent ]]; then
    monarch_root_file_trusted_directory "${parent%/*}" "$trusted_uid" "$stop" || return 1
    install -d -m 0755 -- "$parent" || return 1
  fi
  monarch_root_file_trusted_directory "$parent" "$trusted_uid" "$stop" || return 1
  if [[ -e $lock || -L $lock ]]; then
    monarch_root_file_trusted_source "$lock" "$trusted_uid" "$stop" || return 1
  fi
  if [[ -n $inherited ]]; then
    [[ $inherited =~ ^[0-9]+$ && -f $lock ]] || return 1
    [[ $(stat -Lc '%d:%i' -- "/proc/$$/fd/$inherited") == $(stat -c '%d:%i' -- "$lock") ]] || return 1
    monarch_hibernation_lock_fd=$inherited
  else
    exec {monarch_hibernation_lock_fd}>"$lock" || return 1
    chmod 0600 "$lock" || return 1
    if ! flock -w 60 "$monarch_hibernation_lock_fd"; then
      echo "Another hibernation operation is still running" >&2
      return 1
    fi
  fi
}

monarch_hibernation_require_no_removal() {
  local pending="$system_root/var/lib/monarch/hibernation-remove-rebuild"
  if [[ -e $pending || -L $pending ]]; then
    echo "Hibernation removal is pending; rerun monarch hibernation remove before setup/reconciliation" >&2
    return 1
  fi
}
