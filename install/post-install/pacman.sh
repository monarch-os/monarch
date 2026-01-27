# Configure pacman
if [[ ${OMARCHY_MIRROR:-} == "edge" ]] ; then
  sudo cp -f ~/.local/share/monarch/default/pacman/pacman-edge.conf /etc/pacman.conf
else
  sudo cp -f ~/.local/share/monarch/default/pacman/pacman-stable.conf /etc/pacman.conf
fi
