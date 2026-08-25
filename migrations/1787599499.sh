echo "Enable local crash capture notifications"

SERVICE=monarch-crash-watch.service

mkdir -p "$HOME/.config/systemd/user"
cp "$MONARCH_PATH/config/systemd/user/$SERVICE" "$HOME/.config/systemd/user/$SERVICE"
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE"
