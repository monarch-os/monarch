#!/bin/bash

set -euo pipefail

runtime=${MONARCH_RUNTIME_ROOT:-/usr/share/monarch}
legacy="$HOME/.local/share/monarch"
backup="$HOME/.local/share/monarch-v4"
invitation="$HOME/.config/monarch/hooks/post-boot.d/legacy-runtime-cleanup"

[[ -x $runtime/bin/monarch ]] || exit 0

if [[ -d $legacy && ! -L $legacy ]]; then
  if [[ -e $backup ]]; then
    echo "Cannot archive $legacy: $backup already exists" >&2
    exit 1
  fi
  mv "$legacy" "$backup"
fi

rm -rf "$HOME/.local/state/monarch/migrations"
if [[ $0 != "$invitation" ]]; then
  mv "$0" "$invitation"
fi
"${MONARCH_RECONCILE_BIN:-/usr/bin/monarch-reconcile}" --complete

if ! monarch-notification-wait; then
  exit 1
fi

monarch-notification-send -g "󰆴" \
  "Monarch V5 upgrade complete" \
  "Your previous installation is preserved in ~/.local/share/monarch-v4. Keep it until you are confident the upgrade works." \
  --action "Clean up" monarch-launch-floating-terminal-with-presentation monarch-remove-legacy-runtime

rm -f "$invitation"
