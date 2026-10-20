# Only new installations adopt the default; upgrades preserve the user's shell.
# Deferred provisioning has no account yet and selects Zsh in create_user.
if [[ ${MONARCH_FIRST_INSTALL:-0} == "1" && -n ${MONARCH_INSTALL_USER:-} ]]; then
  [[ -x /bin/zsh ]] || {
    echo "Cannot set the default shell: /bin/zsh is not installed" >&2
    return 1
  }
  usermod -s /bin/zsh "$MONARCH_INSTALL_USER"
fi
