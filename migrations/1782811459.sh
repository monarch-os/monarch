echo "Drop the fixed unit name from the power-profile udev rule so concurrent AC/USB events don't collide and stall wakeup"

# The --unit=monarch-power-profile name meant a still-running invocation from a
# previous power event blocked the next systemd-run, which could stall resume.
# Re-source the install script to rewrite the rule with an auto-generated unit.
if monarch-battery-present; then
  source "$MONARCH_PATH/install/config/powerprofilesctl-rules.sh"
fi
