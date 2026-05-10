# Install Sound Open Firmware for the audio DSP on non-XPS Intel Panther
# Lake systems. XPS PTL stays on linux-ptl, which hard-deps sof-firmware.
# Mainline `linux` only optdeps it, so without this the DSP fails to boot
# and only auto_null shows up in PipeWire.

if monarch-hw-intel-ptl && ! monarch-hw-match "XPS"; then
  monarch-pkg-add sof-firmware
fi
