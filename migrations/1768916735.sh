
echo "Fix microphone gain and audio mixing on Asus ROG laptops"

source "$MONARCH_PATH/install/config/hardware/asus/fix-mic.sh"
source "$MONARCH_PATH/install/config/hardware/asus/fix-audio-mixer.sh"

if monarch-hw-asus-rog; then
  monarch-restart-pipewire
fi
