set -euo pipefail

echo "Reconcile Monarch user state"

legacy_noctalia=0
if monarch-pkg-present noctalia-shell || [[ -f $HOME/.config/noctalia/settings.json ]]; then
  legacy_noctalia=1
fi

if ((legacy_noctalia)); then
  monarch-pkg-add noctalia qrencode
  pkill -f 'qs.*noctalia-shell' 2>/dev/null || true
  monarch-pkg-drop noctalia-shell polkit-gnome

  monarch-refresh-config noctalia/config.toml
  monarch-refresh-config herdr/config.toml

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

mkdir -p "$HOME/.config/noctalia/palettes" "$HOME/.local/share/noctalia/plugins"
cp -f "$MONARCH_PATH"/config/noctalia/palettes/*.json "$HOME/.config/noctalia/palettes/"
cp -rf "$MONARCH_PATH"/default/noctalia/plugins/. "$HOME/.local/share/noctalia/plugins/"

for shell_rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -f $shell_rc ]] || continue
  sed -i 's|source ~/.local/share/monarch/default/zsh/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/zsh/rc"|' "$shell_rc"
  sed -i 's|source ~/.local/share/monarch/default/bash/rc|source "${MONARCH_PATH:-/usr/share/monarch}/default/bash/rc"|' "$shell_rc"
done

if [[ -f $HOME/.config/uwsm/env ]]; then
  sed -i 's|^export MONARCH_PATH=.*|export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}|' \
    "$HOME/.config/uwsm/env"
fi

if ((legacy_noctalia)) || [[ $MONARCH_SOURCE_ROOT == "$HOME/.local/share/monarch" ]] ||
  grep -qE '(\.local/share/monarch|qs.*noctalia)' "$HOME/.config/niri/config.kdl" 2>/dev/null; then
  monarch-refresh-niri
fi

plugin_hook="$HOME/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
if noctalia msg status >/dev/null 2>&1; then
  for plugin in monarch/indicators monarch/agents monarch/menu monarch/wifi-qr monarch/network monarch/display monarch/theme; do
    noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || true
  done
  monarch-theme-apply >/dev/null 2>&1 || true
  rm -f "$plugin_hook"
else
  mkdir -p "$(dirname "$plugin_hook")"
  cp "$MONARCH_PATH/install/reconcile/noctalia-plugins.sh" "$plugin_hook"
  chmod 755 "$plugin_hook"
fi

legacy_root="$HOME/.local/share/monarch"
if [[ $MONARCH_SOURCE_ROOT == "$legacy_root" && -d $legacy_root && ! -L $legacy_root ]]; then
  finalize_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
  mkdir -p "$(dirname "$finalize_hook")"
  cp "$MONARCH_PATH/install/reconcile/packaged-runtime.sh" "$finalize_hook"
  chmod 755 "$finalize_hook"
fi
