set -euo pipefail

if settings=$(/usr/bin/pacman -Q monarch-settings 2>/dev/null); then
  files=$(/usr/bin/pacman -Qql monarch-settings)
  if [[ -z $files ]]; then
    runtime=$(/usr/bin/pacman -Q monarch)
    if [[ ${runtime#monarch } != "${settings#monarch-settings }" ]]; then
      printf 'Cannot remove monarch-settings: installed versions differ (%s; %s). Update both packages together.\n' \
        "$runtime" "$settings" >&2
      exit 1
    fi
    /usr/bin/env MONARCH_UPDATE_PACMAN=1 /usr/bin/pacman -R --noconfirm monarch-settings
  fi
fi
