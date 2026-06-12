echo "Retire the standalone monzed package in favor of the Noctalia zed user-template"

# Pre-Niri, Zed theming was a separate `monzed` package: it generated
# ~/.config/zed/themes/monzed.json from the old Monarch theme palette and hooked
# into monarch's theme-set.d. Theming is now delegated to Noctalia, which renders
# Zed via the [templates.zed] user-template (zed.json -> noctalia.json). Tear
# down the old bridge and converge onto the shipped default config.

registry="$HOME/.config/noctalia/user-templates.toml"
zed_settings="$HOME/.config/zed/settings.json"

# 1. Remove the dead monzed theme-set hook, generated theme, and state.
rm -f "$HOME/.config/monarch/hooks/theme-set.d/monzed"
rm -f "$HOME/.config/zed/themes/monzed.json"
rm -rf "$HOME/.local/share/monzed"

# 2. Uninstall the monzed package if it is still installed.
if monarch-pkg-present monzed; then
  sudo pacman -Rns --noconfirm monzed || true
fi

# 3. Seed the Noctalia zed template input and register it, matching the shipped
#    default so existing installs render the theme on the next color generation.
monarch-refresh-config noctalia/templates/zed.json || true
if [[ -f $registry ]] && ! grep -q '\[templates.zed\]' "$registry"; then
  cat >> "$registry" << 'EOF'

[templates.zed]
input_path = "~/.config/noctalia/templates/zed.json"
output_path = "~/.config/zed/themes/noctalia.json"
EOF
fi

# 4. Repoint Zed only if it is still pinned to the now-deleted "Monzed" theme.
if [[ -f $zed_settings ]] && grep -q '"Monzed"' "$zed_settings"; then
  sed -i -E 's|"theme"[[:space:]]*:[[:space:]]*"Monzed"|"theme": { "mode": "system", "light": "Noctalia Light", "dark": "Noctalia Dark" }|' "$zed_settings"
fi
