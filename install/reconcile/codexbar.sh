monarch_reconcile_codexbar() {
  local source="${MONARCH_CODEXBAR_PLUGIN_ROOT:-$MONARCH_PATH/default/noctalia/plugins}/monarch-agents"

  [[ -f $source/plugin.toml ]] && monarch-cmd-present codexbar || {
    echo "CodexBar CLI and Monarch Agents must be installed before migrating agent usage" >&2
    return 1
  }

  codexbar config validate >/dev/null || return 1
  [[ ! -f $HOME/.local/share/noctalia/plugins/monarch-agents/service.luau ]] || plugins_changed=true
  python3 "$MONARCH_PATH/install/reconcile/codexbar.py" || return 1
  monarch_reconcile_managed_tree "$source" \
    "$HOME/.local/share/noctalia/plugins/monarch-agents" plugins_changed
}
