set -euo pipefail

echo "Reconcile Monarch user state"

source "$MONARCH_PATH/install/reconcile/config-files.sh"

monarch_reconcile_seeded_file \
  "$MONARCH_PATH/config/alacritty/monarch-text-size.toml" \
  "$HOME/.config/alacritty/monarch-text-size.toml"

for palette in "$MONARCH_PATH"/config/noctalia/palettes/*.json; do
  monarch_reconcile_managed_file "$palette" \
    "$HOME/.config/noctalia/palettes/$(basename "$palette")"
done

for plugin in "$MONARCH_PATH"/default/noctalia/plugins/monarch-*; do
  monarch_reconcile_managed_tree "$plugin" \
    "$HOME/.local/share/noctalia/plugins/$(basename "$plugin")"
done

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
