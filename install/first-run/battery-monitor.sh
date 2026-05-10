if monarch-battery-present; then
  powerprofilesctl set power-saver || true

  # Enable battery monitoring timer for low battery notifications
  systemctl --user enable --now monarch-battery-monitor.timer
else
  powerprofilesctl set balanced || true
fi
