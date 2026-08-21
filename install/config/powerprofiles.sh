# The profile follows the power source through monarch-powerprofiles-set, which
# runs as the user: at login from niri's autostart, and on every transition from
# monarch-battery-monitor's timer. A udev rule used to do it and could not —
# udev runs as root, so the profile it remembered was written into /root and
# never met the one the user picked, which is why it only ever set a hardcoded
# one.
if monarch-battery-present; then
  sudo systemctl enable power-profiles-daemon
fi
