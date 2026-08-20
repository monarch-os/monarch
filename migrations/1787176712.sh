echo "Hand the polkit prompt to Noctalia and retire the GTK agent"

# Noctalia v5 registers its own polkit agent and draws the prompt in the Monarch
# theme; it ships disabled, so until now niri spawned polkit-gnome instead. Fresh
# installs get the key from config/noctalia/config.toml and the autostart without
# that line; existing installs are switched over here.
#
# Order matters. Polkit admits one agent per session: while polkit-gnome holds
# it, Noctalia's registration fails and does not retry on its own. So the GTK
# agent is stopped first, and the config edit lands after — Noctalia re-syncs the
# agent on every config reload, which is what registers it without a relogin.

pkill -f polkit-gnome-authentication-agent-1 2>/dev/null || true

CONFIG="$HOME/.config/noctalia/config.toml"

if [[ -f $CONFIG ]] && ! grep -q '^[[:space:]]*polkit_agent' "$CONFIG"; then
  if grep -q '^\[shell\]' "$CONFIG"; then
    sed -i '/^\[shell\]$/a polkit_agent = true' "$CONFIG"
  else
    # No [shell] table to extend — append one rather than editing a section that
    # is not there. A second [shell] header would make the whole file unparseable,
    # hence the check above.
    printf '\n[shell]\npolkit_agent = true\n' >>"$CONFIG"
  fi
fi

# The autostart line is included straight from the Monarch tree, so it is already
# gone for the next session; the package is what is left to drop.
monarch-pkg-drop polkit-gnome

# Noctalia only reaches the D-Bus session bus while it is running. When it is
# not, the key is in place and the agent registers at the next start.
if ! noctalia msg status >/dev/null 2>&1; then
  echo "  Noctalia is not running; its polkit agent will register on next login."
fi
