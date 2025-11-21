echo "Pull packages from stable Arch mirror"

monarch-refresh-pacman-mirrorlist stable
sudo pacman -Syu
