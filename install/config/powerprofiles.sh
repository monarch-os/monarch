# The profile follows the source through monarch-powerprofiles-set, which runs
# as the user. The udev rule this replaces ran as root, so what it remembered
# landed in /root and never met the user's pick.
if monarch-battery-present; then
  sudo systemctl enable power-profiles-daemon
fi
