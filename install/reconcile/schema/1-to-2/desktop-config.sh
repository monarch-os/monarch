set -euo pipefail

for shell_rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -f $shell_rc ]] || continue
  sed --follow-symlinks -i \
    's|source ~/.local/share/monarch/default/zsh/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/zsh/rc"|' \
    "$shell_rc"
  sed --follow-symlinks -i \
    's|source ~/.local/share/monarch/default/bash/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/bash/rc"|' \
    "$shell_rc"
done

if [[ -f $HOME/.config/uwsm/env ]]; then
  sed --follow-symlinks -i \
    's|^export MONARCH_PATH=.*|export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}|' \
    "$HOME/.config/uwsm/env"
fi

monarch-refresh-niri
