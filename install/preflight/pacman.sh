if [[ -n ${MONARCH_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  monarch-pkg-add base-devel

  # Configure pacman
  sudo cp -f ~/.local/share/monarch/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf /etc/pacman.conf
  sudo cp -f ~/.local/share/monarch/default/pacman/mirrorlist /etc/pacman.d/mirrorlist

  # Cachy OS
  sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key F3B607488DB35A47

  # Omarchy
  sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

  # Monarch
  sudo pacman-key --recv-keys 519BC3D5AEA652C94F89F0AAC13B3766D969CE82 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 519BC3D5AEA652C94F89F0AAC13B3766D969CE82

  sudo pacman -Sy
  monarch-pkg-add omarchy-keyring  monarch-keyring

  # Refresh all repos
  sudo pacman -Syyuu --noconfirm
fi
