monarch_reconcile_chat_privacy() {
  local legacy_config=$HOME/.local/state/monarch/chat-privacy.kdl
  local flag=$HOME/.local/state/monarch/toggles/chat-privacy-off

  if [[ -f $legacy_config && ! -s $legacy_config && ! -f $flag ]]; then
    "$MONARCH_PATH/bin/monarch-toggle-chat-privacy" off || return 1
  else
    "$MONARCH_PATH/bin/monarch-toggle-chat-privacy" init || return 1
  fi

  rm -f "$legacy_config"
}

monarch_reconcile_chat_privacy
