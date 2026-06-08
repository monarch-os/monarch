#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export MONARCH_ONLINE_INSTALL=true

ansi_art='███████████████████████████████████████████████████████████████████
█▌                                                               ▐█
█▌ ███    ███  ██████  ███    ██  █████  ██████   ██████ ██   ██ ▐█
█▌ ████  ████ ██    ██ ████   ██ ██   ██ ██   ██ ██      ██   ██ ▐█
█▌ ██ ████ ██ ██    ██ ██ ██  ██ ███████ ██████  ██      ███████ ▐█
█▌ ██  ██  ██ ██    ██ ██  ██ ██ ██   ██ ██   ██ ██      ██   ██ ▐█
█▌ ██      ██  ██████  ██   ████ ██   ██ ██   ██  ██████ ██   ██ ▐█
█▌                                                               ▐█
███████████████████████████████████████████████████████████████████'

clear
echo -e "\n$ansi_art\n"

# Use custom branch if instructed, otherwise default to main
MONARCH_REF="${MONARCH_REF:-main}"

echo 'Server = https://archlinux.cachyos.org/repo/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null

sudo pacman -Syu --noconfirm --needed git

# Use custom repo if specified, otherwise default to y0no/monarch
MONARCH_REPO="${MONARCH_REPO:-https://github.com/monarch-os/monarch.git}"

echo -e "\nCloning Monarch from: ${MONARCH_REPO}"
rm -rf ~/.local/share/monarch/
git clone "${MONARCH_REPO}" ~/.local/share/monarch >/dev/null

echo -e "\e[32mUsing branch: $MONARCH_REF\e[0m"
cd ~/.local/share/monarch
git fetch origin "${MONARCH_REF}" && git checkout "${MONARCH_REF}"
cd -

echo -e "\nInstallation starting..."
source ~/.local/share/monarch/install.sh
