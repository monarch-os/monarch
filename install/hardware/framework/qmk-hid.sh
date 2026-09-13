# Allow unprivileged access to the Framework 16 keyboard for RGB control via qmk_hid.

if monarch-hw-framework16; then
  sudo mkdir -p /etc/udev/rules.d
  if [[ ! -f /etc/udev/rules.d/50-framework16-qmk-hid.rules ]]; then
    sudo cp -f "$MONARCH_PATH/default/udev/framework16-qmk-hid.rules" /etc/udev/rules.d/50-framework16-qmk-hid.rules
  fi
fi
