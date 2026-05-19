echo "Switch /etc/pacman.d/mirrorlist to the unified CachyOS-based mirrorlist"

sudo cp -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
sudo cp -f "$MONARCH_PATH/default/pacman/mirrorlist" /etc/pacman.d/mirrorlist

# Refresh keyrings before hitting the new mirrors
monarch-update-keyring

# Force a full DB resync against the new mirrors
sudo pacman -Syy --noconfirm
