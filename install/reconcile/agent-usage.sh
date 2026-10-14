monarch_prepare_agent_usage_transition() {
  local plugin="$HOME/.local/share/noctalia/plugins/monarch-agents"
  [[ -f $plugin/service.luau && ! -L $plugin ]] || return 0
  local source="$MONARCH_PATH/default/noctalia/plugins/monarch-agents"

  [[ -f $source/plugin.toml ]] && monarch-cmd-present codexbar || {
    echo "CodexBar CLI and Monarch Agents must be installed before migrating agent usage" >&2
    return 1
  }

  python3 "$MONARCH_PATH/install/reconcile/agent-usage.py"
}
