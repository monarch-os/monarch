# Configure pacman

sudo cp -f ~/.local/share/monarch/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf /etc/pacman.conf
sudo cp -f ~/.local/share/monarch/default/pacman/mirrorlist /etc/pacman.d/mirrorlist
