echo "Install the Monarch Welcome Noctalia plugin and retire the toast-stack onboarding"

# 1. Symlink Monarch-shipped Noctalia plugins into the user's plugin directory.
plugin_root="$HOME/.config/noctalia/plugins"
plugins_file="$HOME/.config/noctalia/plugins.json"
mkdir -p "$plugin_root"
[[ -f $plugins_file ]] || echo '{"version":2,"states":{},"sources":[]}' >"$plugins_file"

for plugin in "$MONARCH_PATH/config/noctalia/plugins"/*/; do
  [[ -d $plugin ]] || continue
  name=$(basename "$plugin")
  target="$plugin_root/$name"
  if [[ -L $target || ! -e $target ]]; then
    ln -sfn "$plugin" "$target"
  fi
  # Noctalia ships plugins disabled by default; mark Monarch-shipped ones enabled.
  if command -v jq >/dev/null; then
    tmp=$(mktemp)
    if jq --arg id "$name" '.states[$id] = ((.states[$id] // {}) | .enabled = true)' "$plugins_file" >"$tmp"; then
      mv "$tmp" "$plugins_file"
    else
      rm -f "$tmp"
    fi
  fi
done

# 2. Restart Noctalia so PluginRegistry picks up the symlink + enabled state.
monarch-restart-noctalia || true
