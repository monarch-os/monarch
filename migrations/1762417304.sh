echo "Replace bluetooth GUI with TUI"

monarch-pkg-add bluetui
monarch-pkg-drop blueberry

if ! grep -q "monarch-launch-bluetooth" ~/.config/waybar/config.jsonc; then
  sed -i 's/blueberry/monarch-launch-bluetooth/' ~/.config/waybar/config.jsonc
fi
