echo "Install the Monarch Welcome Noctalia plugin and retire the toast-stack onboarding"

# 1. Symlink Monarch-shipped Noctalia plugins into the user's plugin directory.
plugin_root="$HOME/.config/noctalia/plugins"
mkdir -p "$plugin_root"
for plugin in "$MONARCH_PATH/config/noctalia/plugins"/*/; do
  [[ -d $plugin ]] || continue
  name=$(basename "$plugin")
  target="$plugin_root/$name"
  if [[ -L $target || ! -e $target ]]; then
    ln -sfn "$plugin" "$target"
  fi
done

# 2. Restart Noctalia so PluginRegistry picks up the new plugin.
monarch-restart-noctalia || true
