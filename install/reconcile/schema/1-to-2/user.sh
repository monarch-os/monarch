set -euo pipefail

legacy_noctalia=0
if monarch-pkg-present noctalia-shell || [[ -f $HOME/.config/noctalia/settings.json ]]; then
  legacy_noctalia=1
fi

if ((legacy_noctalia)); then
  monarch-pkg-add noctalia qrencode
  pkill -f 'qs.*noctalia-shell' 2>/dev/null || true
  monarch-pkg-drop noctalia-shell polkit-gnome monarch-welcome

  monarch-refresh-config noctalia/config.toml
  monarch-refresh-config herdr/config.toml
  monarch-refresh-config fastfetch/config.jsonc

  rm -f "$HOME"/.config/noctalia/settings.json "$HOME"/.config/noctalia/settings.json.bak.*
  rm -f "$HOME"/.config/noctalia/user-templates.toml "$HOME"/.config/noctalia/user-templates.toml.bak.*
  rm -f "$HOME/.config/noctalia/plugins.json"
  rm -rf "$HOME/.config/noctalia/colorschemes" "$HOME/.config/noctalia/plugins"
  rm -f "$HOME/.cache/noctalia/shell-state.json" "$HOME/.cache/noctalia/wallpapers.json"
  rm -rf "$HOME/.cache/noctalia-qs" "$HOME/.config/noctalia/templates"
  rm -f "$HOME/.config/environment.d/noctalia-fingerprint.conf"

  if [[ -f $HOME/.local/state/monarch/fingerprint-enabled ]]; then
    cat >"$HOME/.config/noctalia/monarch-fingerprint.toml" <<'EOF'
[lockscreen]
fingerprint = true
EOF
  fi
fi

for shell_rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -f $shell_rc ]] || continue
  sed -i 's|source ~/.local/share/monarch/default/zsh/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/zsh/rc"|' "$shell_rc"
  sed -i 's|source ~/.local/share/monarch/default/bash/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/bash/rc"|' "$shell_rc"
done

if [[ -f $HOME/.config/uwsm/env ]]; then
  sed -i 's|^export MONARCH_PATH=.*|export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}|' \
    "$HOME/.config/uwsm/env"
fi

monarch-refresh-niri

if ((legacy_noctalia)); then
  monarch-refresh-noctalia
  for _ in $(seq 1 50); do
    noctalia msg status >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

legacy_root="$HOME/.local/share/monarch"
if [[ $MONARCH_SOURCE_ROOT == "$legacy_root" && -d $legacy_root && ! -L $legacy_root ]]; then
  finalize_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
  mkdir -p "$(dirname "$finalize_hook")"
  cp "$MONARCH_PATH/install/reconcile/packaged-runtime.sh" "$finalize_hook"
  chmod 755 "$finalize_hook"
fi
