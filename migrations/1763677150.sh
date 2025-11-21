echo "Change waybar monarch icon"

sed -i 's/\\ue900//' ~/.config/waybar/config.jsonc
sed -i 's/\\ue900//' ~/.config/fastfetch/config.jsonc

rm ~/.local/share/fonts/monarch.ttf

monarch-restart-waybar
