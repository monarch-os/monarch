echo "Add visual theme and unlock selectors"

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-theme"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-theme"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi
