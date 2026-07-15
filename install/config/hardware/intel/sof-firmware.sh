# Install Sound Open Firmware for the audio DSP on Intel systems that need it.
# The sof-audio-pci-intel-* driver family requires sof-firmware to initialise
# the DSP; the CachyOS kernel (like mainline) only optdeps it, so without this
# the DSP fails to boot and PipeWire exposes only a Dummy Output sink. This
# affects Arrow Lake, Meteor Lake, Tiger Lake, Alder Lake, Wildcat Lake,
# Panther Lake, and similar platforms.

if monarch-hw-intel-sof; then
  monarch-pkg-add sof-firmware
fi
