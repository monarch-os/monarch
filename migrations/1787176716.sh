echo "Give herdr its config back"

# v4 rendered ~/.config/herdr/config.toml from a Noctalia user-template. v5
# renders only catalog ids, so nothing has rendered it since the port: a fresh
# install has no herdr config at all and runs on herdr's built-in defaults, while
# an upgraded one keeps whatever v4 last wrote, frozen on that day's colors.
# Monarch ships the file directly now, and it needs no repainting: herdr reads the
# terminal palette over OSC, so it follows the scheme on its own.

monarch-refresh-config herdr/config.toml

rm -f "$HOME/.config/noctalia/templates/herdr.toml"

# Registered by migration 1781015444. v5 never read it; drop it so the registry
# stops naming an input that no longer exists.
TEMPLATES="$HOME/.config/noctalia/user-templates.toml"
if [[ -f $TEMPLATES ]] && grep -q '^\[templates\.herdr\]' "$TEMPLATES"; then
  echo "  Dropping [templates.herdr] from the v4 template registry"
  awk '/^\[templates\.herdr\]/ { skip = 1; next } /^\[/ { skip = 0 } !skip' \
    "$TEMPLATES" >"$TEMPLATES.tmp" && mv "$TEMPLATES.tmp" "$TEMPLATES"
fi

monarch-restart-herdr || true
