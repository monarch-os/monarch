echo "Install the Monarch display panel"

# Per-output scale and on-off, which no part of Noctalia offers: its control
# center Monitor tab has the brightness slider and nothing else. Opens from the
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

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/display >/dev/null 2>&1 || true
else
  echo "  Noctalia is not running; the display panel will be enabled on next login."
fi
