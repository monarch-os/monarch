echo "Strip dead Monarch-theme-engine references from kitty/ghostty configs"

# The Hyprland->Noctalia switch (migration 1779188617) removed
# ~/.config/monarch/current/theme and repaired alacritty/btop/helix, but left
# kitty and ghostty still including the now-missing per-terminal theme files —
# kitty errors about the missing include on every launch. kitty also carried
# three invalid config keys (window_padding_height, show_window_resize_notification,
# single_instance) that it warns about each time. Theming is already handled by
# Noctalia (kitty via its BEGIN_KITTY_THEME include of current-theme.conf;
# ghostty via `theme = noctalia`), so we only strip the dead lines in place,
# mirroring how the original migration patched alacritty.

kitty_cfg="$HOME/.config/kitty/kitty.conf"
if [[ -f $kitty_cfg ]]; then
  sed -i \
    -e '\#monarch/current/theme#d' \
    -e '/^[[:space:]]*window_padding_height\b/d' \
    -e '/^[[:space:]]*show_window_resize_notification\b/d' \
    -e '/^[[:space:]]*single_instance\b/d' \
    "$kitty_cfg"
fi

ghostty_cfg="$HOME/.config/ghostty/config"
if [[ -f $ghostty_cfg ]]; then
  sed -i '\#monarch/current/theme#d' "$ghostty_cfg"
fi
