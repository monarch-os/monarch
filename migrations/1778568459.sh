echo "Switch Niri config to include-based loader (no more generated config.kdl)"

# The first Hyprland → Niri migration generated a fully-inlined config.kdl by
# concatenating templates. That tripped Niri's "duplicate top-level section"
# rule whenever the user override re-declared `layout`. The new layout splits
# the defaults across multiple files and uses Niri's native `include`
# directive — config.kdl is now a tiny stable loader.
#
# This migration: redeploy the loader for users who already ran the previous
# migration, then re-render theme templates so ~/.config/monarch/current/theme/
# contains niri-colors.kdl.

if command -v monarch-refresh-niri >/dev/null 2>&1; then
  monarch-refresh-niri || true
fi

# Re-apply the current theme so niri-colors.kdl is generated.
if [[ -f $HOME/.config/monarch/current/theme.name ]]; then
  current_theme=$(cat "$HOME/.config/monarch/current/theme.name")
  if [[ -n $current_theme ]] && command -v monarch-theme-set >/dev/null 2>&1; then
    MONARCH_THEME_SKIP_BACKGROUND=1 monarch-theme-set "$current_theme" >/dev/null 2>&1 || true
  fi
fi
