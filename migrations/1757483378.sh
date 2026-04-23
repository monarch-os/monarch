echo "6Ghz Wi-Fi + Intel graphics acceleration for existing installations"

bash "$MONARCH_PATH/install/config/hardware/set-wireless-regdom.sh"
bash "$MONARCH_PATH/install/config/hardware/intel/video-acceleration.sh"
