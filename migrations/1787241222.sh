echo "Install the Monarch network panel"

# The bar's network widget and the panel behind it: connection state, Wi-Fi
# band, DNS provider and the network list, backed by monarch-network-status,
# monarch-wifi-list and the wifi action commands. It stands in for Noctalia's
# stock `network` widget, which has the list and the radio but none of the rest.
#
# Fresh installs get the plugin from install/config/config.sh, the lane from
# config/noctalia/config.toml and the enable from install/first-run/welcome.sh;
# existing installs need all three here. Seeding a plugin only makes v5 discover
# it — a discovered plugin stays disabled — so the enable is what puts the
# widget on the bar. It needs a running shell and is a no-op when the socket is
# not listening; the same migration re-run after login finishes the job.

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-network"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-network"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

# Swap the stock widget out of every bar lane the user has, theirs included:
# leaving both would show the same connection twice.
config="$HOME/.config/noctalia/config.toml"
if [[ -f $config ]] && grep -q '^[[:space:]]*"network",\?[[:space:]]*$' "$config" &&
  ! grep -q 'monarch/network:network' "$config"; then
  echo "  Replacing the stock network widget with Monarch's in the bar."
  # The comma is optional: the stock entry is last in some hand-edited lanes.
  # Skipped entirely when ours is already there, or the two would sit side by
  # side reporting the same connection.
  sed -i 's|^\([[:space:]]*\)"network"\(,\?\)[[:space:]]*$|\1"monarch/network:network"\2|' "$config"
fi

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/network >/dev/null 2>&1 || true
else
  echo "  Noctalia is not running; the network plugin will be enabled on next login."
fi
