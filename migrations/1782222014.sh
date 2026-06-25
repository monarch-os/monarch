echo "Enable the user ssh-agent so SSH key passphrases are cached for the session"

uwsm_env="$HOME/.config/uwsm/env"
if [[ -f $uwsm_env ]] && ! grep -q 'SSH_AUTH_SOCK' "$uwsm_env"; then
  printf '\n# SSH agent (graphical session only, not shell rc — keeps agent forwarding intact)\nexport SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"\n' >>"$uwsm_env"
fi

bash "$MONARCH_PATH/install/config/ssh-agent.sh"
