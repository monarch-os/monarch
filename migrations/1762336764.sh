echo "Update waybar styling"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

cat <<< $(jq 'del(."hyprland/workspaces"."format-icons".default)' "$WAYBAR_CONFIG") > "$WAYBAR_CONFIG"
cat <<< $(jq 'del(."hyprland/workspaces"."format-icons".active)' "$WAYBAR_CONFIG") > "$WAYBAR_CONFIG"
cat <<< $(jq '."hyprland/workspaces"."format-icons" += {"10":"10"}' "$WAYBAR_CONFIG") > "$WAYBAR_CONFIG"
cat <<< $(jq 'del(."hyprland/workspaces"."persistent-workspaces")' "$WAYBAR_CONFIG") > "$WAYBAR_CONFIG"

monarch-refresh-config waybar/style.css
monarch-restart-waybar