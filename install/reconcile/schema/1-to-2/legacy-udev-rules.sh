set -euo pipefail

if (( EUID == 0 )); then
  rules_dir=/etc/udev/rules.d
  marker_dir=/var/lib/monarch/reconcile/legacy-udev-rules
  udev_control=/run/udev/control
  install_command=/usr/bin/install
  mv_command=/usr/bin/mv
  readlink_command=/usr/bin/readlink
  rm_command=/usr/bin/rm
  stat_command=/usr/bin/stat
  udevadm_command=/usr/bin/udevadm
else
  rules_dir=${MONARCH_UDEV_RULES_DIR:?}
  marker_dir=${MONARCH_UDEV_MARKER_DIR:?}
  udev_control=${MONARCH_UDEV_CONTROL:?}
  install_command=${MONARCH_INSTALL_COMMAND:-/usr/bin/install}
  mv_command=${MONARCH_MV_COMMAND:-/usr/bin/mv}
  readlink_command=${MONARCH_READLINK_COMMAND:-/usr/bin/readlink}
  rm_command=${MONARCH_RM_COMMAND:-/usr/bin/rm}
  stat_command=${MONARCH_STAT_COMMAND:-/usr/bin/stat}
  udevadm_command=${MONARCH_UDEVADM_COMMAND:-/usr/bin/udevadm}
fi

mkdir -p "$marker_dir"

active_rule_runs_helper() {
  local file="$1" binary="$2"
  local line logical=""

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line == *\\ ]]; then
      logical+=${line%\\}
      continue
    fi
    logical+=$line
    rule_line_runs_helper "$logical" "$binary" && return 0
    logical=""
  done <"$file"

  return 1
}

rule_line_runs_helper() {
  local line="$1" binary="$2" token="" character previous="" command
  local quote=0 index
  local pattern='^[[:space:]]*RUN([[:space:]]*\{(program)?\})?[[:space:]]*(\+|:)?=[[:space:]]*(e)?"([^"]*)"[[:space:]]*$'
  local helper_pattern="/bin/$binary([[:space:]]|$)"

  for ((index = 0; index < ${#line}; index++)); do
    character=${line:index:1}
    if [[ $character == '"' && $previous != '\' ]]; then
      quote=$((1 - quote))
    elif ((quote == 0)) && [[ $character == "#" ]]; then
      break
    elif ((quote == 0)) && [[ $character == "," ]]; then
      if [[ $token =~ $pattern ]]; then
        command=${BASH_REMATCH[5]}
        [[ $command =~ $helper_pattern ]] && return 0
      fi
      token=""
      previous=$character
      continue
    fi
    token+=$character
    previous=$character
  done

  if [[ $token =~ $pattern ]]; then
    command=${BASH_REMATCH[5]}
    [[ $command =~ $helper_pattern ]] && return 0
  fi
  return 1
}

entry_identity() {
  "$stat_command" --format='%d:%i:%F' -- "$1" 2>/dev/null
}

exact_generated_rule() {
  local file="$1" binary="$2" prefix suffix path
  local -a lines

  mapfile -t lines <"$file"
  (( ${#lines[@]} == 2 )) || return 1

  if [[ $binary == "monarch-powerprofiles-set" ]]; then
    prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile-battery --property=After=power-profiles-daemon.service '
    suffix='/bin/monarch-powerprofiles-set battery"'
    if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
      path=${lines[0]#"$prefix"}; path=${path%"$suffix"}
      [[ $path == /* && $path != *'"'* ]] || return 1
      [[ ${lines[1]} == 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-power-profile-ac --property=After=power-profiles-daemon.service '"$path"'/bin/monarch-powerprofiles-set ac"' ]]
      return
    fi

    for unit in '--unit=monarch-power-profile ' ''; do
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect '"$unit"'--property=After=power-profiles-daemon.service '
      suffix='/bin/monarch-powerprofiles-set"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        path=${lines[0]#"$prefix"}; path=${path%"$suffix"}
        [[ $path == /* && $path != *'"'* ]] || return 1
        [[ ${lines[1]} == 'SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect '"$unit"'--property=After=power-profiles-daemon.service '"$path"'/bin/monarch-powerprofiles-set"' ]]
        return
      fi
    done
  else
    prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="'
    suffix='/bin/monarch-wifi-powersave on"'
    if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
      path=${lines[0]#"$prefix"}; path=${path%"$suffix"}
      [[ $path == /* && $path != *'"'* ]] || return 1
      [[ ${lines[1]} == 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="'"$path"'/bin/monarch-wifi-powersave off"' ]]
      return
    fi

    prefix='  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-wifi-powersave-on '
    suffix='/bin/monarch-wifi-powersave on"'
    if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
      path=${lines[0]#"$prefix"}; path=${path%"$suffix"}
      [[ $path == /* && $path != *'"'* ]] || return 1
      [[ ${lines[1]} == '  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=monarch-wifi-powersave-off '"$path"'/bin/monarch-wifi-powersave off"' ]]
      return
    fi
  fi

  return 1
}

finish_reload() {
  local marker="$1"

  if [[ -e $udev_control ]] && ! "$udevadm_command" control --reload; then
    echo "Could not reload udev after repairing a legacy rule" >&2
    return 1
  fi
  "$rm_command" -f -- "$marker" || return 1
}

quarantine_rule() {
  local file="$1" marker="$2" expected_identity="$3"
  local backup="$file.monarch-disabled" suffix=0

  while [[ -e $backup || -L $backup ]]; do
    ((++suffix))
    backup="$file.monarch-disabled.$suffix"
  done
  [[ $(entry_identity "$file") == "$expected_identity" ]] || return 2
  if ! "$install_command" -Dm644 /dev/null "$marker"; then
    echo "Could not record legacy udev repair state" >&2
    return 1
  fi
  if ! "$mv_command" --no-clobber -- "$file" "$backup"; then
    echo "Could not quarantine legacy udev rule: $file" >&2
    return 1
  fi
  if [[ -e $file || -L $file ]]; then
    echo "Could not quarantine legacy udev rule: $file" >&2
    return 1
  fi
  quarantined_rule=$backup
  finish_reload "$marker"
}

repair_rule() {
  local name="$1" binary="$2"
  local file="$rules_dir/$name" marker="$marker_dir/$name.reload"
  local identity attempt quarantine_status settled=0

  for ((attempt = 0; attempt < 3; attempt++)); do
    if ! identity=$(entry_identity "$file"); then
      if [[ -e $file || -L $file ]]; then
        continue
      fi
      settled=1
      break
    fi
    if [[ -L $file ]]; then
      if [[ $("$readlink_command" "$file") == "/dev/null" ]]; then
        settled=1
        break
      fi
      if quarantine_rule "$file" "$marker" "$identity"; then
        settled=1
        break
      else
        quarantine_status=$?
      fi
      ((quarantine_status == 2)) && continue
      return 1
    elif [[ ! -f $file ]]; then
      if quarantine_rule "$file" "$marker" "$identity"; then
        settled=1
        break
      else
        quarantine_status=$?
      fi
      ((quarantine_status == 2)) && continue
      return 1
    elif exact_generated_rule "$file" "$binary"; then
      if quarantine_rule "$file" "$marker" "$identity"; then
        if [[ -f $quarantined_rule ]] && exact_generated_rule "$quarantined_rule" "$binary"; then
          "$rm_command" -f -- "$quarantined_rule"
        fi
        settled=1
        break
      else
        quarantine_status=$?
      fi
      ((quarantine_status == 2)) && continue
      return 1
    elif active_rule_runs_helper "$file" "$binary"; then
      if quarantine_rule "$file" "$marker" "$identity"; then
        settled=1
        break
      else
        quarantine_status=$?
      fi
      ((quarantine_status == 2)) && continue
      return 1
    else
      settled=1
      break
    fi
  done

  if ((settled == 0)); then
    echo "Legacy udev rule changed repeatedly during reconciliation: $file" >&2
    return 1
  fi
  [[ ! -e $marker ]] || finish_reload "$marker"
}

repair_rule 99-power-profile.rules monarch-powerprofiles-set
repair_rule 99-wifi-powersave.rules monarch-wifi-powersave
