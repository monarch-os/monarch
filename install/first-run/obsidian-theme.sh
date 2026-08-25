if monarch-cmd-present obsidian; then
  systemctl --user enable --now monarch-obsidian-theme.path
  monarch-obsidian-theme || true
fi
