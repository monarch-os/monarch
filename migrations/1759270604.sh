echo "Update Hyprlock with better placeholder position and show all fail text (skipped — Monarch no longer ships Hyprlock)"

# Hyprlock has been replaced by swaylock; this historical migration is now a no-op.
if monarch-cmd-present monarch-refresh-hyprlock; then
  monarch-refresh-hyprlock
fi
