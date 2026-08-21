echo "Install the Monarch display panel"

# Fresh installs get this from install/config/config.sh and first-run/welcome.sh;
# existing ones need both here. Seeding only makes v5 discover the plugin, and a
# discovered plugin stays disabled, so the enable is what makes the panel exist.

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-display"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-display"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

# Replacing the stock widget rather than joining it: one screen glyph in the lane.
config="$HOME/.config/noctalia/config.toml"
if [[ -f $config ]] && grep -q '^[[:space:]]*"brightness",\?[[:space:]]*$' "$config" &&
  ! grep -q 'monarch/display:display' "$config"; then
  echo "  Replacing the stock brightness widget with Monarch's display pill."
  sed -i 's|^\([[:space:]]*\)"brightness"\(,\?\)[[:space:]]*$|\1"monarch/display:display"\2|' "$config"
fi

# A [widget.brightness] left behind names a widget no lane holds, which v5 warns
# about on every load.
if [[ -f $config ]] && ! grep -q '"brightness"' "$config"; then
  sed -i '/^\[widget\.brightness\]$/,/^$/d' "$config"
fi

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/display >/dev/null 2>&1 || true
else
  echo "  Noctalia is not running; the display panel will be enabled on next login."
fi
