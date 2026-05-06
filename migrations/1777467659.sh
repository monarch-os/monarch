echo "Rename lock screen command in Hypridle config"

if grep -q 'monarch-lock-screen' ~/.config/hypr/hypridle.conf; then
  sed -i 's/monarch-lock-screen/monarch-system-lock/g' ~/.config/hypr/hypridle.conf
  monarch-restart-hypridle
fi
