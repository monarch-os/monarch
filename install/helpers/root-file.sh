source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

monarch_root_file_trusted_directory() {
  local directory="$1" trusted_uid="$2" stop="$3" canonical uid mode

  [[ $stop == / || $directory == "$stop" || $directory == "$stop/"* ]] || return 1
  [[ -d $directory && ! -L $directory ]] || return 1
  canonical=$(/usr/bin/realpath -e -- "$directory") || return 1
  [[ $canonical == "$directory" ]] || return 1

  while :; do
    uid=$(/usr/bin/stat -c '%u' -- "$directory") || return 1
    mode=$(/usr/bin/stat -c '%a' -- "$directory") || return 1
    ((uid == trusted_uid && (8#$mode & 8#022) == 0)) || return 1
    [[ $directory == "$stop" ]] && return 0
    directory=${directory%/*}
    [[ -n $directory ]] || directory=/
  done
}

monarch_root_file_trusted_source() {
  local source="$1" trusted_uid="$2" stop="$3" canonical uid mode

  [[ -f $source && ! -L $source ]] || return 1
  canonical=$(/usr/bin/realpath -e -- "$source") || return 1
  [[ $canonical == "$source" ]] || return 1
  uid=$(/usr/bin/stat -c '%u' -- "$source") || return 1
  mode=$(/usr/bin/stat -c '%a' -- "$source") || return 1
  ((uid == trusted_uid && (8#$mode & 8#022) == 0)) || return 1
  monarch_root_file_trusted_directory "${source%/*}" "$trusted_uid" "$stop"
}

monarch_root_file_context() {
  local -n system_root_ref=$1 runtime_root_ref=$2 trusted_uid_ref=$3 stop_ref=$4 test_mode_ref=$5

  system_root_ref=
  runtime_root_ref=/usr/share/monarch
  trusted_uid_ref=0
  stop_ref=/
  test_mode_ref=0
  if ((EUID != 0)) &&
    [[ -n ${MONARCH_ROOT_FILE_TEST_ROOT:-} || -n ${MONARCH_ROOT_FILE_TEST_RUNTIME:-} ]]; then
    [[ -n ${MONARCH_ROOT_FILE_TEST_ROOT:-} && -n ${MONARCH_ROOT_FILE_TEST_RUNTIME:-} ]] || return 1
    system_root_ref=$(/usr/bin/realpath -e -- "$MONARCH_ROOT_FILE_TEST_ROOT") || return 1
    runtime_root_ref=$(/usr/bin/realpath -e -- "$MONARCH_ROOT_FILE_TEST_RUNTIME") || return 1
    [[ $system_root_ref == /* && -d $system_root_ref && ! -L $system_root_ref ]] || return 1
    [[ $runtime_root_ref == "$system_root_ref/"* ]] || return 1
    trusted_uid_ref=$EUID
    stop_ref=$system_root_ref
    test_mode_ref=1
  fi
}

monarch_root_file_run() {
  local test_mode=$1 option value
  local -a arguments=()
  shift

  if ((test_mode)); then
    if [[ $1 == /usr/bin/install ]]; then
      arguments+=("$1")
      shift
      while (($#)); do
        case $1 in
          -o | -g)
            option=$1
            shift
            (($#)) || return 1
            value=$1
            if [[ $value == root ]]; then
              [[ $option == -o ]] && value=$EUID || value=$(/usr/bin/id -g)
            fi
            arguments+=("$option" "$value")
            ;;
          *) arguments+=("$1") ;;
        esac
        shift
      done
      "${arguments[@]}"
      return
    fi
    "$@"
  else
    as_root "$@"
  fi
}

monarch_install_root_file() {
  local asset="$1" system_root runtime_root trusted_uid stop test_mode
  local source destination mode parent stage prefix suffix

  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1

  case $asset in
    keyboard-backlight)
      source="$runtime_root/default/systemd/system-sleep/keyboard-backlight"
      destination="$system_root/usr/lib/systemd/system-sleep/keyboard-backlight"
      mode=0755
      ;;
    force-igpu)
      source="$runtime_root/default/systemd/system-sleep/force-igpu"
      destination="$system_root/usr/lib/systemd/system-sleep/force-igpu"
      mode=0755
      ;;
    delay-start)
      source="$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf"
      destination="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
      mode=0644
      ;;
    *) return 1 ;;
  esac

  monarch_root_file_trusted_source "$source" "$trusted_uid" "$stop" || return 1
  parent=${destination%/*}
  if [[ ! -e $parent && ! -L $parent ]]; then
    monarch_root_file_trusted_directory "${parent%/*}" "$trusted_uid" "$stop" || return 1
    monarch_root_file_run "$test_mode" /usr/bin/install -d -m 0755 -o root -g root -- "$parent" || return 1
  fi
  monarch_root_file_trusted_directory "$parent" "$trusted_uid" "$stop" || return 1

  prefix="$parent/.${destination##*/}.monarch."
  stage=$(monarch_root_file_run "$test_mode" /usr/bin/mktemp -- "${prefix}XXXXXX") || return 1
  suffix=${stage#"$prefix"}
  if [[ $stage != "$prefix"* || ! $suffix =~ ^[[:alnum:]]{6}$ ]]; then
    return 1
  fi

  if monarch_root_file_run "$test_mode" /usr/bin/install -m "$mode" -o root -g root -T "$source" "$stage" &&
    monarch_root_file_run "$test_mode" /usr/bin/mv -Tf -- "$stage" "$destination"; then
    return 0
  fi

  [[ $stage == "$prefix"* && $suffix =~ ^[[:alnum:]]{6}$ ]] &&
    monarch_root_file_run "$test_mode" /usr/bin/rm -f -- "$stage"
  return 1
}

monarch_configure_supergfxd() {
  local target_mode=$1 system_root runtime_root trusted_uid stop test_mode
  local config stage prefix suffix mode gid

  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1
  config="$system_root/etc/supergfxd.conf"
  monarch_root_file_trusted_source "$config" "$trusted_uid" "$stop" || return 1
  case $target_mode in
    Hybrid)
      [[ $(monarch_root_file_run "$test_mode" /usr/bin/grep -Ec \
        '^[[:space:]]*"mode"[[:space:]]*:' "$config") == 1 ]] || return 1
      ;;
    Integrated)
      [[ $(monarch_root_file_run "$test_mode" /usr/bin/grep -Ec \
        '^[[:space:]]*"mode"[[:space:]]*:' "$config") == 1 &&
        $(monarch_root_file_run "$test_mode" /usr/bin/grep -Ec \
          '^[[:space:]]*"vfio_enable"[[:space:]]*:' "$config") == 1 ]] || return 1
      ;;
    *) return 1 ;;
  esac

  mode=$(/usr/bin/stat -c '%a' -- "$config") || return 1
  gid=$(/usr/bin/stat -c '%g' -- "$config") || return 1
  prefix="${config%/*}/.${config##*/}.monarch."
  stage=$(monarch_root_file_run "$test_mode" /usr/bin/mktemp -- "${prefix}XXXXXX") || return 1
  suffix=${stage#"$prefix"}
  [[ $stage == "$prefix"* && $suffix =~ ^[[:alnum:]]{6}$ ]] || return 1

  if ! monarch_root_file_run "$test_mode" /usr/bin/install -m "$mode" -o root -g "$gid" \
    -T -- "$config" "$stage"; then
    monarch_root_file_run "$test_mode" /usr/bin/rm -f -- "$stage"
    return 1
  fi

  case $target_mode in
    Hybrid)
      monarch_root_file_run "$test_mode" /usr/bin/sed -Ei \
        -e 's/^([[:space:]]*"mode"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"Hybrid"/' \
        "$stage" &&
        monarch_root_file_run "$test_mode" /usr/bin/grep -Eq \
          '^[[:space:]]*"mode"[[:space:]]*:[[:space:]]*"Hybrid"' "$stage"
      ;;
    Integrated)
      monarch_root_file_run "$test_mode" /usr/bin/sed -Ei \
        -e 's/^([[:space:]]*"mode"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"Integrated"/' \
        -e 's/^([[:space:]]*"vfio_enable"[[:space:]]*:[[:space:]]*)(true|false)/\1true/' \
        "$stage" &&
        monarch_root_file_run "$test_mode" /usr/bin/grep -Eq \
          '^[[:space:]]*"mode"[[:space:]]*:[[:space:]]*"Integrated"' "$stage" &&
        monarch_root_file_run "$test_mode" /usr/bin/grep -Eq \
          '^[[:space:]]*"vfio_enable"[[:space:]]*:[[:space:]]*true' "$stage"
      ;;
  esac && monarch_root_file_run "$test_mode" /usr/bin/mv -Tf -- "$stage" "$config" && return 0

  monarch_root_file_run "$test_mode" /usr/bin/rm -f -- "$stage"
  return 1
}

monarch_root_file_can_remove() {
  local asset="$1" system_root runtime_root trusted_uid stop test_mode source destination parent

  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1
  case $asset in
    force-igpu)
      source="$runtime_root/default/systemd/system-sleep/force-igpu"
      destination="$system_root/usr/lib/systemd/system-sleep/force-igpu"
      ;;
    delay-start)
      source="$runtime_root/default/systemd/supergfxd.service.d/delay-start.conf"
      destination="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
      ;;
    *) return 1 ;;
  esac

  monarch_root_file_trusted_source "$source" "$trusted_uid" "$stop" || return 1
  parent=${destination%/*}
  [[ -e $parent || -L $parent ]] || return 0
  monarch_root_file_trusted_directory "$parent" "$trusted_uid" "$stop" || return 1
  [[ -e $destination || -L $destination ]] || return 0
  [[ -f $destination && ! -L $destination ]] || return 1
  /usr/bin/cmp -s -- "$source" "$destination" || return 1
}

monarch_remove_root_file() {
  local asset="$1" system_root runtime_root trusted_uid stop test_mode destination

  monarch_root_file_can_remove "$asset" || return 1
  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1
  case $asset in
    force-igpu) destination="$system_root/usr/lib/systemd/system-sleep/force-igpu" ;;
    delay-start) destination="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf" ;;
    *) return 1 ;;
  esac

  [[ -e $destination || -L $destination ]] || return 0
  monarch_root_file_run "$test_mode" /usr/bin/rm -f -- "$destination"
}
