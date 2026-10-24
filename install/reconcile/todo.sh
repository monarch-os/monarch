# Upgrade entry point: optional/older packages keep their existing integration.
source "${BASH_SOURCE[0]%/*}/../helpers/todo.sh"

monarch_reconcile_todo() {
  monarch-cmd-present monarch-todo || return 0
  monarch-todo setup-desktop --help >/dev/null 2>&1 || return 0
  monarch_configure_todo "$1"
}
