echo "Add touchpad gestures for close, fullscreen, menu, and terminal"

if ! grep -q "gesture = 3, down, mod: ALT, close" ~/.config/hypr/input.conf; then
  sed -i '/^gesture = 3, horizontal, workspace$/a gesture = 3, down, mod: ALT, close\ngesture = 3, up, mod: SUPER, scale: 1.5, fullscreen\ngesture = 4, up, dispatcher, exec, monarch-menu\ngesture = 4, down, dispatcher, exec, xdg-terminal-exec' ~/.config/hypr/input.conf
fi
