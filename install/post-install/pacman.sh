# Configure pacman

cp -f "$MONARCH_PATH"/default/pacman/pacman.conf /etc/pacman.conf
cp -f "$MONARCH_PATH"/default/pacman/mirrorlist /etc/pacman.d/mirrorlist
pacman-key --populate archlinux cachyos monarch
