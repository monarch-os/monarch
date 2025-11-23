echo "Fix capslock issue on hyprland"

sed -i 's/compose:caps/compose:caps_toggle/' ~/.config/hypr/input.conf
