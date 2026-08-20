echo "Install the Wi-Fi QR sharing panel"

# Share the connected network as a scannable QR code: monarch-wifi-qr renders it
# with qrencode, the monarch/wifi-qr Noctalia panel shows it, and the menu's
# Share > Wi-Fi row opens that panel.
#
# Fresh installs get the package from install/monarch-base.packages, the plugin
# from install/config/config.sh and the enable from install/first-run/welcome.sh;
# existing installs need all three here. Seeding a plugin only makes v5 discover
# it — a discovered plugin stays disabled — so the enable is what actually puts
# the card on screen. It needs a running shell and is a no-op when the socket is
# not listening; the same migration re-run after login finishes the job.

monarch-pkg-add qrencode

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-wifi-qr"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-wifi-qr"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/wifi-qr >/dev/null 2>&1 || true
else
  echo "  Noctalia is not running; the Wi-Fi QR plugin will be enabled on next login."
fi
