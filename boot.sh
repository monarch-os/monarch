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

if ! sudo pacman -Syu --noconfirm --needed git; then
  echo -e "\e[31mFailed to install git. Check your network connection and pacman mirrors, then re-run.\e[0m" >&2
  exit 1
fi

# Use custom repo if specified, otherwise default to monarch-os/monarch
MONARCH_REPO="${MONARCH_REPO:-https://github.com/monarch-os/monarch.git}"

echo -e "\nCloning Monarch from: ${MONARCH_REPO}"
rm -rf ~/.local/share/monarch/
if ! git clone "${MONARCH_REPO}" ~/.local/share/monarch; then
  echo -e "\e[31mFailed to clone Monarch from ${MONARCH_REPO}. Check your network connection, then re-run.\e[0m" >&2
  exit 1
fi

echo -e "\e[32mUsing branch: $MONARCH_REF\e[0m"
cd ~/.local/share/monarch
if ! git fetch origin "${MONARCH_REF}" || ! git checkout "${MONARCH_REF}"; then
  echo -e "\e[31mFailed to check out branch '${MONARCH_REF}'. Verify it exists in ${MONARCH_REPO}.\e[0m" >&2
  exit 1
fi
cd -

echo -e "\nInstallation starting..."
source ~/.local/share/monarch/install.sh
