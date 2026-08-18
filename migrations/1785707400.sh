echo "Install the monarch-menu Noctalia panel plugin"

# The menu is a Noctalia panel now: bin/monarch-menu only routes to it. Fresh
# installs get the plugin from install/config/config.sh and have it enabled by
# install/first-run/welcome.sh; existing installs need both steps here.
#
# Seeding a plugin only makes v5 discover it — a discovered plugin stays
# disabled — so the enable is what actually puts the menu on screen. It needs a
# running shell, and is a no-op when the socket is not listening; the same
# migration re-run after login finishes the job.

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-menu"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-menu"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/menu >/dev/null 2>&1 || true
else
  echo "  Noctalia is not running; the menu plugin will be enabled on next login."
fi
