# Install Sound Open Firmware for Intel audio DSPs. The sof-audio-pci-intel-*
# driver family requires this firmware; without it PipeWire exposes only a
# Dummy Output sink.

if monarch-hw-intel-sof; then
  monarch-pkg-add sof-firmware
fi
