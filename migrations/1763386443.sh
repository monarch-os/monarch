echo "Uniquely identify terminal apps with custom app-ids using monarch-launch-tui"

# Replace terminal -e calls with monarch-launch-tui in bindings
sed -i 's/\$terminal -e \([^ ]*\)/monarch-launch-tui \1/g' ~/.config/hypr/bindings.conf

# Update waybar to use monarch-launch-or-focus with monarch-launch-tui for TUI apps
sed -i 's|xdg-terminal-exec btop|monarch-launch-or-focus-tui btop|' ~/.config/waybar/config.jsonc
sed -i 's|xdg-terminal-exec --app-id=com\.monarch\.Wiremix -e wiremix|monarch-launch-or-focus-tui wiremix|' ~/.config/waybar/config.jsonc
