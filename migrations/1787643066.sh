echo "Watch for new Obsidian vaults and apply their Noctalia theme"

if monarch-cmd-present obsidian; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$MONARCH_PATH/config/systemd/user/monarch-obsidian-theme."{path,service} \
    "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now monarch-obsidian-theme.path
  monarch-obsidian-theme || true
fi
