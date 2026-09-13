set -euo pipefail

sudoers_dir=${MONARCH_SUDOERS_DIR:-/etc/sudoers.d}

active_lines() {
  local file="$1" line trimmed
  local -a parts

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z $trimmed ]] && continue
    if [[ $trimmed == \#* ]] &&
      [[ ! $trimmed =~ ^#include(dir)?[[:blank:]] ]] &&
      [[ ! $trimmed =~ ^#-?[0-9] ]]; then
      continue
    fi
    [[ $trimmed != *\\ ]] || return 1
    read -ra parts <<<"$trimmed"
    printf '%s\n' "${parts[*]}"
  done <"$file"
}

first_run_generated() {
  local file="$1" line user command generated_user="" content
  local seen_cleanup_alias=0 seen_symlink_alias=0
  local -A seen=()
  local spec='^([^[:space:]]+) ALL=\(ALL\) NOPASSWD: (.+)$'

  content=$(active_lines "$file") || return 1
  [[ -n $content ]] || return 1

  while IFS= read -r line; do
    case "$line" in
    "Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf")
      (( ! seen_symlink_alias )) || return 1
      seen_symlink_alias=1
      continue
      ;;
    "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run" | \
      "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/99-monarch-installer-reboot" | \
      "Cmnd_Alias FIRST_RUN_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/first-run")
      (( ! seen_cleanup_alias )) || return 1
      seen_cleanup_alias=1
      continue
      ;;
    esac

    [[ $line =~ $spec ]] || return 1
    user=${BASH_REMATCH[1]}
    command=${BASH_REMATCH[2]}
    [[ $user =~ ^[A-Za-z_][A-Za-z0-9_.-]*\$?$ ]] || return 1
    [[ -z $generated_user || $user == "$generated_user" ]] || return 1
    generated_user=$user
    [[ ! ${seen[$command]+present} ]] || return 1
    seen[$command]=1

    case "$command" in
    /usr/bin/systemctl | /usr/bin/ufw | /usr/bin/ufw-docker | \
      /usr/bin/gtk-update-icon-cache | /usr/bin/udevadm | \
      "/usr/bin/tee /etc/udev/rules.d/*" | SYMLINK_RESOLVED)
      ;;
    FIRST_RUN_CLEANUP | "/bin/rm -f /etc/sudoers.d/first-run")
      ;;
    *) return 1 ;;
    esac
  done <<<"$content"

  (( seen_cleanup_alias && seen_symlink_alias )) || return 1
  for command in /usr/bin/systemctl /usr/bin/ufw /usr/bin/ufw-docker \
    /usr/bin/gtk-update-icon-cache SYMLINK_RESOLVED FIRST_RUN_CLEANUP; do
    [[ ${seen[$command]+present} ]] || return 1
  done
}

tsui_generated() {
  local file="$1" line user command count=0 content
  local spec='^[^[:space:]]+ ALL=\(ALL\) NOPASSWD: ([^[:space:]]+)$'

  content=$(active_lines "$file") || return 1
  [[ -n $content ]] || return 1

  while IFS= read -r line; do
    ((++count))
    (( count == 1 )) || return 1
    [[ $line =~ $spec ]] || return 1
    command=${BASH_REMATCH[1]}
    user=${line%% *}
    [[ $user =~ ^[A-Za-z_][A-Za-z0-9_.-]*\$?$ ]] || return 1
  done <<<"$content"

  (( count == 1 )) && [[ ${command##*/} == "tsui" ]]
}

remove_if_generated() {
  local file="$1" predicate="$2"

  [[ -e $file || -L $file ]] || return 0
  [[ -f $file && ! -L $file ]] || return 0
  "$predicate" "$file" || return 0
  rm -f -- "$file"
}

remove_if_generated "$sudoers_dir/first-run" first_run_generated
remove_if_generated "$sudoers_dir/tsui" tsui_generated
