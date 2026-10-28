set -euo pipefail

if /usr/bin/pacman -Qq monarch-settings >/dev/null 2>&1; then
  files=$(/usr/bin/pacman -Qql monarch-settings)
  if [[ -z $files ]]; then
    /usr/bin/env MONARCH_UPDATE_PACMAN=1 /usr/bin/pacman -R --noconfirm monarch-settings
  fi
fi
