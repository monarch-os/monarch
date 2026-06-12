if [[ -n ${MONARCH_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  monarch-pkg-add base-devel

  # Configure pacman
  sudo cp -f "$MONARCH_PATH"/default/pacman/pacman.conf /etc/pacman.conf
  sudo cp -f "$MONARCH_PATH"/default/pacman/mirrorlist /etc/pacman.d/mirrorlist

  # Import and locally sign the repo keys listed in keys.conf
  while read -r key_id keyserver; do
    [[ -z $key_id || $key_id == \#* ]] && continue
    sudo pacman-key --recv-keys "$key_id" --keyserver "$keyserver"
    sudo pacman-key --lsign-key "$key_id"
  done <"$MONARCH_PATH"/default/pacman/keys.conf

  sudo pacman -Sy
  monarch-pkg-add monarch-keyring

  # Refresh all repos
  sudo pacman -Syyuu --noconfirm
fi
