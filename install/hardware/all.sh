run_logged "$MONARCH_INSTALL/hardware/asus-rog.sh"
run_logged "$MONARCH_INSTALL/hardware/framework16.sh"
run_logged "$MONARCH_INSTALL/hardware/dell-xps-touchpad-haptics.sh"
run_logged "$MONARCH_INSTALL/hardware/surface.sh"

run_logged "$MONARCH_INSTALL/hardware/network.sh"
run_logged "$MONARCH_INSTALL/hardware/set-wireless-regdom.sh"
run_logged "$MONARCH_INSTALL/hardware/fix-fkeys.sh"
run_logged "$MONARCH_INSTALL/hardware/fix-synaptic-touchpad.sh"
run_logged "$MONARCH_INSTALL/hardware/bluetooth.sh"
run_logged "$MONARCH_INSTALL/hardware/nvidia.sh"
run_logged "$MONARCH_INSTALL/hardware/vulkan.sh"

run_logged "$MONARCH_INSTALL/hardware/intel/video-acceleration.sh"
run_logged "$MONARCH_INSTALL/hardware/intel/lpmd.sh"
run_logged "$MONARCH_INSTALL/hardware/intel/thermald.sh"
# Monarch keeps the selected CachyOS kernel on Panther Lake rather than
# replacing it with the reference distribution's linux-ptl package.
run_logged "$MONARCH_INSTALL/hardware/intel/ipu7-camera.sh"
run_logged "$MONARCH_INSTALL/hardware/intel/fred.sh"
run_logged "$MONARCH_INSTALL/hardware/intel/fix-wifi7-eht.sh"
run_logged "$MONARCH_INSTALL/hardware/intel/sof-firmware.sh"

# Rebuilds the boot image, so it has to follow the Panther Lake kernel swap
# above rather than sit with the other Dell leaf at the top of this file.
run_logged "$MONARCH_INSTALL/hardware/dell-xps13-sidecar-amps.sh"

run_logged "$MONARCH_INSTALL/hardware/asus/fix-asus-ptl-display-backlight.sh"
run_logged "$MONARCH_INSTALL/hardware/asus/fix-asus-ptl-b9406-display.sh"
run_logged "$MONARCH_INSTALL/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
run_logged "$MONARCH_INSTALL/hardware/asus/fix-z13-touchpad.sh"

run_logged "$MONARCH_INSTALL/hardware/framework/qmk-hid.sh"

run_logged "$MONARCH_INSTALL/hardware/apple/fix-spi-keyboard.sh"
run_logged "$MONARCH_INSTALL/hardware/apple/fix-suspend-nvme.sh"
run_logged "$MONARCH_INSTALL/hardware/apple/fix-t2.sh"
run_logged "$MONARCH_INSTALL/hardware/apple/fix-brcmfmac-supplicant.sh"

run_logged "$MONARCH_INSTALL/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh"

run_logged "$MONARCH_INSTALL/hardware/fix-bcm43xx.sh"
run_logged "$MONARCH_INSTALL/hardware/fix-surface-keyboard.sh"
run_logged "$MONARCH_INSTALL/hardware/fix-yt6801-ethernet-adapter.sh"
run_logged "$MONARCH_INSTALL/hardware/fix-tuxedo-backlight.sh"
run_logged "$MONARCH_INSTALL/hardware/speaker-tuning.sh"
run_logged "$MONARCH_INSTALL/hardware/pacman.sh"
