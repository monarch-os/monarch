echo "Add right-click terminal action to waybar monarch menu icon"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ -f "$WAYBAR_CONFIG" ]] && ! grep -A5 '"custom/monarch"' "$WAYBAR_CONFIG" | grep -q '"on-click-right"'; then
  sed -i '/"on-click": "monarch-menu",/a\    "on-click-right": "monarch-launch-terminal",' "$WAYBAR_CONFIG"
  monarch-state set restart-waybar-required
fi