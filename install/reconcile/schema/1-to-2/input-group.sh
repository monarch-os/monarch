set -euo pipefail

if id -nG "$USER" | grep -qw input; then
  if pacman -Qq ydotool &>/dev/null; then
    echo "Keeping $USER in the input group: ydotool is installed."
  else
    sudo gpasswd -d "$USER" input >/dev/null
    echo "Removed $USER from the input group. Log out and back in to apply."
    monarch-state set reboot-required
  fi
fi
