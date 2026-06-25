# Enable the user ssh-agent (socket-activated) and default to caching keys in it
systemctl --user enable ssh-agent.socket

printf 'AddKeysToAgent yes\n' | sudo tee /etc/ssh/ssh_config.d/10-monarch.conf >/dev/null
