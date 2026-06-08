# Install Sound Open Firmware for the audio DSP on Intel Panther Lake
# systems. The CachyOS kernel (like mainline) only optdeps sof-firmware, so
# without this the DSP fails to boot and only auto_null shows up in PipeWire.

if monarch-hw-intel-ptl; then
  monarch-pkg-add sof-firmware
fi
