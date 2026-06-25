# Enable the user ssh-agent (socket-activated) and add keys to it on first use
systemctl --user enable ssh-agent.socket

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh_config="$HOME/.ssh/config"
if ! grep -qi 'AddKeysToAgent' "$ssh_config" 2>/dev/null; then
  { printf 'AddKeysToAgent yes\n\n'; [[ -f $ssh_config ]] && cat "$ssh_config"; } >"$ssh_config.tmp"
  mv "$ssh_config.tmp" "$ssh_config"
  chmod 600 "$ssh_config"
fi
