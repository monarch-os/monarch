echo "Install sof-firmware for all Intel SOF audio DSP platforms (Arrow Lake, Meteor Lake, etc.)"

# Intel SOF platforms beyond Panther Lake (Arrow Lake, Meteor Lake, Tiger Lake,
# Alder Lake, Wildcat Lake) were not covered by the original sof-firmware install
# guard, which only matched Panther Lake. Without sof-firmware the DSP fails to
# boot and PipeWire exposes only a Dummy Output. Install it now for all
# qualifying Intel systems.

if monarch-hw-intel-sof && monarch-pkg-missing sof-firmware; then
  monarch-pkg-add sof-firmware
  monarch-state set reboot-required
fi
