set -euo pipefail

echo "Reconcile Monarch user state"

source "$MONARCH_PATH/install/reconcile/config-files.sh"
source "$MONARCH_PATH/install/reconcile/noctalia-activation.sh"

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
defer_plugin_activation() {
  local hook_dir hook_tmp

  hook_dir=$(dirname "$plugin_hook")
  mkdir -p "$hook_dir"
  hook_tmp=$(mktemp "$hook_dir/.noctalia-v5-plugins.XXXXXX")
  trap 'rm -f "$hook_tmp"' EXIT
  install -m 0755 "$MONARCH_PATH/install/reconcile/noctalia-plugins.sh" "$hook_tmp"
  mv -fT "$hook_tmp" "$plugin_hook"
  trap - EXIT
}

if monarch_noctalia_wait 1; then
  plugins_ready=true
  monarch_noctalia_enable_plugins >/dev/null 2>&1 || plugins_ready=false
  monarch-theme-apply >/dev/null 2>&1 || true
  if [[ $plugins_ready == "true" ]]; then
    rm -f "$plugin_hook"
  else
    defer_plugin_activation
  fi
else
  defer_plugin_activation
fi
