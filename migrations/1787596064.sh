echo "Add disk speed testing to the Monarch network plugin"

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-network"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-network"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi
