monarch_browser_desktop_id_valid() {
  [[ $1 =~ ^[[:alnum:]_.+-]+\.desktop$ ]]
}

monarch_browser_default_desktop() {
  local desktop_id

  if ! desktop_id=$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null) ||
    ! monarch_browser_desktop_id_valid "$desktop_id"; then
    desktop_id=""
  fi

  if [[ -z $desktop_id ]]; then
    desktop_id=$(xdg-mime query default x-scheme-handler/https 2>/dev/null) || return 1
  fi

  monarch_browser_desktop_id_valid "$desktop_id" || return 1
  printf '%s\n' "$desktop_id"
}

monarch_browser_desktop_exec() {
  local desktop_id="$1"
  local application_dir desktop_file exec_line executable

  monarch_browser_desktop_id_valid "$desktop_id" || return 1

  for application_dir in \
    "$HOME/.local/share/applications" \
    "$HOME/.nix-profile/share/applications" \
    /usr/local/share/applications \
    /usr/share/applications; do
    desktop_file="$application_dir/$desktop_id"
    [[ -f $desktop_file ]] || continue
    exec_line=$(sed -n '/^\[Desktop Entry\]$/,/^\[/{s/^Exec=//p}' "$desktop_file" | head -1)
    [[ -n $exec_line ]] || continue
    executable=${exec_line%%[[:space:]]*}
    [[ $executable =~ ^[[:alnum:]_.+@/-]+$ ]] || return 1

    if [[ $executable == */* ]]; then
      [[ $executable == /* && -x $executable ]] || return 1
    else
      command -v "$executable" >/dev/null 2>&1 || return 1
    fi

    printf '%s\n' "$executable"
    return 0
  done

  return 1
}
