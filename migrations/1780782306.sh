echo "Make the Noctalia session menu compact (no header, no keybinds)"

# Monarch now ships a compact session-menu default (config/noctalia/settings.json):
# largeButtonsStyle=false with showHeader/showKeybinds off, instead of Noctalia's
# stock large-button row. Fresh installs get it via the shipped settings.json;
# existing v0.11.0 installs already have a ~/.config/noctalia/settings.json without
# a sessionMenu block, so merge the override into the live file (hot-reloaded).
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f $cfg ]]; then
  tmp=$(mktemp)
  if jq '.sessionMenu = (.sessionMenu // {})
         | .sessionMenu.largeButtonsStyle = false
         | .sessionMenu.showHeader = false
         | .sessionMenu.showKeybinds = false' \
       "$cfg" >"$tmp"; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"
    echo "  Warning: could not update $cfg; set the sessionMenu block manually." >&2
  fi
fi
