echo "Tear down the legacy Monarch theme engine (theming is delegated to Noctalia)"

# Theming moved fully to Noctalia. Monarch now ships a single "Monarch" color
# scheme (dark + light) and only a thin residual layer (monarch-theme-apply,
# wired to Noctalia's colorGeneration hook). This migration drops the old
# home-grown theme-engine state and makes sure the shipped scheme + settings
# (hooks, templates, wallpaper) are in place.

# 1. Deploy the shipped Monarch scheme as a real file (older installs symlinked it
#    into ~/.config/monarch/current/theme/) and refresh settings.json so the
#    Noctalia hook/templates/wallpaper defaults land. Backups are kept by
#    monarch-refresh-config and auto-removed when nothing changed.
rm -f "$HOME/.config/noctalia/colorschemes/Monarch/Monarch.json" # drop any old symlink
monarch-refresh-config noctalia/colorschemes/Monarch/Monarch.json || true
monarch-refresh-config noctalia/settings.json || true

# 2. Remove the retired theme-engine state.
rm -rf "$HOME/.config/monarch/themes" \
  "$HOME/.config/monarch/current/theme" \
  "$HOME/.config/monarch/current/next-theme" \
  "$HOME/.config/monarch/current/theme.name"

# 3. Drop symlinks that pointed at the old per-theme rendered files.
rm -f "$HOME/.config/btop/themes/current.theme" # btop now uses color_theme="noctalia"
rm -f "$HOME/.config/helix/themes/monarch.toml" # helix now uses theme="noctalia"

# 4. Point Helix at Noctalia's theme if it still references the old Monarch one.
if [[ -f $HOME/.config/helix/config.toml ]]; then
  sed -i 's/^theme = "monarch"$/theme = "noctalia"/' "$HOME/.config/helix/config.toml"
fi

# 5. Apply the residual system theming layer for the current scheme. Redirect
#    stdout so it runs non-interactively (skips the heavy Plymouth/sudo path;
#    run `monarch theme apply` by hand to re-theme the boot screen).
monarch-cmd-present monarch-theme-apply && monarch-theme-apply >/dev/null 2>&1 || true
