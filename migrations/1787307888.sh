echo "Install the Monarch display panel"

# Per-output scale and on-off, which no part of Noctalia offers, and the
# brightness its control center Monitor tab keeps to itself. Opens from the
# menu, under Hardware > Displays.
#
# Fresh installs get the plugin from install/config/config.sh and the enable
# from install/first-run/welcome.sh; existing installs need both here. Seeding a
# plugin only makes v5 discover it — a discovered plugin stays disabled — so the
# enable is what makes the panel exist. It needs a running shell and is a no-op
# when the socket is not listening; the same migration re-run after login
# finishes the job.

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-display"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-display"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

# The pill takes the place of the stock `brightness` widget rather than joining
# it, so the right lane keeps one screen glyph, and its panel carries a slider
# per screen — everything the stock one reached, and the scale and on-off no
# part of v5 has.
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
