monarch_install_packaged_runtime() {
  local legacy_supported=${1:-false}

  if [[ $legacy_supported != "true" ]]; then
    monarch-pkg-add monarch
    return
  fi

  local system_root=${MONARCH_LEGACY_SYSTEM_ROOT:-/}
  local -a legacy_files=(
    etc/sudoers.d/monarch-tzupdate
    usr/lib/systemd/system-sleep/unmount-fuse
    usr/local/share/wayland-sessions/monarch.desktop
    usr/share/sddm/niri.kdl
  )
  local -a legacy_trees=(
    usr/share/plymouth/themes/monarch
    usr/share/sddm/themes/monarch
  )
  local -a existing_files=()
  local -a overwrite_args=()
  local path file relative

  for path in "${legacy_files[@]}"; do
    sudo test -e "$system_root/$path" || continue
    existing_files+=("$system_root/$path")
    overwrite_args+=(--overwrite "$path")
  done

  for path in "${legacy_trees[@]}"; do
    [[ -e $system_root/$path || -L $system_root/$path ]] || continue
    while IFS= read -r -d '' file; do
      existing_files+=("$file")
      relative=${file#"$system_root"}
      overwrite_args+=(--overwrite "${relative#/}")
    done < <(find "$system_root/$path" \( -type f -o -type l \) -print0)
  done

  if (( ${#existing_files[@]} == 0 )); then
    monarch-pkg-add monarch
    return
  fi

  for file in "${existing_files[@]}"; do
    if pacman -Qo "$file" &>/dev/null; then
      echo "Refusing to replace package-owned legacy path: $file" >&2
      return 1
    fi
  done

  sudo env MONARCH_UPDATE_PACMAN=1 pacman -S --noconfirm --needed \
    "${overwrite_args[@]}" monarch
}
