echo "Show battery status notification on right-click of the waybar battery icon"

if ! grep -q 'monarch-battery-status' ~/.config/waybar/config.jsonc; then
  sed -i '/"on-click": "monarch-menu power",/a\    "on-click-right": "notify-send -u low \\"$(monarch-battery-status)\\"",' ~/.config/waybar/config.jsonc
  monarch-restart-waybar
fi
