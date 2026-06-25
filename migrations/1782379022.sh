echo "Enable the user ssh-agent and default SSH keys to it via a global drop-in"

uwsm_env="$HOME/.config/uwsm/env"
if [[ -f $uwsm_env ]] && ! grep -q 'SSH_AUTH_SOCK' "$uwsm_env"; then
  printf '\n# SSH agent (graphical session only, not shell rc — keeps agent forwarding intact)\nexport SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"\n' >>"$uwsm_env"
fi

bash "$MONARCH_PATH/install/config/ssh-agent.sh"
