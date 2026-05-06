echo "Enable FRED on Intel Panther Lake systems"

DEFAULT_LIMINE="/etc/default/limine"

if monarch-hw-intel-ptl && [[ -f $DEFAULT_LIMINE ]] && ! grep -q 'fred=on' "$DEFAULT_LIMINE"; then
  source "$MONARCH_PATH/install/config/hardware/intel/fred.sh"

  sudo limine-update
fi
