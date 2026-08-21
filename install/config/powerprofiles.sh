# monarch-powerprofiles-set carries this now, as the user; see 1787300769.
if monarch-battery-present; then
  sudo systemctl enable power-profiles-daemon
fi
