echo "Update hyprland keybindings (skipped — Monarch no longer ships Hyprland)"

# Hyprland has been replaced by Niri; this historical migration is now a no-op.
if monarch-cmd-present monarch-refresh-hyprland; then
  monarch-refresh-hyprland
fi
