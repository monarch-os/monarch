echo "Fix disable-while-typing on ASUS ROG Flow Z13 detachable keyboard"

source $MONARCH_PATH/install/config/hardware/asus/fix-z13-touchpad.sh

if [[ -f /etc/udev/rules.d/99-monarch-asus-z13-touchpad.rules ]]; then
  monarch-state set reboot-required
fi
