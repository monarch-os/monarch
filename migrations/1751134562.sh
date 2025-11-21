echo "Ensure all indexes and packages are up to date"

monarch-refresh-pacman
sudo pacman -Syu --noconfirm