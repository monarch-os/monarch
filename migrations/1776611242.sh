echo "Reactivate internal display when external display is removed (skipped — Monarch no longer ships monarch-hyprland-monitor-watch)"

# Niri handles output hot-plug natively; no monitor-watch daemon is needed.
if monarch-cmd-present monarch-hyprland-monitor-watch; then
  uwsm-app -- monarch-hyprland-monitor-watch &
fi
