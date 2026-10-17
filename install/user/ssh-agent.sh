# Match config/uwsm/env. The socket starts the agent on demand after login.
# Installation is followed by reboot; do not start user services mid-install.
systemctl --user enable ssh-agent.socket
