if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then
  monarch-notification-action "󰖩" "Setup Wi-Fi" \
    "Arrow to navigate, Enter to select" \
    "Open Wi-Fi" monarch-launch-wifi
  monarch-notification-action "" "Update System" \
    "When you have internet, click to update the system." \
    "Update now" monarch-launch-floating-terminal-with-presentation monarch-update
else
  monarch-notification-action "" "Update System" \
    "Click to update the system." \
    "Update now" monarch-launch-floating-terminal-with-presentation monarch-update
fi
