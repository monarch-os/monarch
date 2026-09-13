set -euo pipefail

source "$MONARCH_PATH/bin/monarch-windows-vm"

monarch_reconcile_windows_vm() {
  local WINDOWS_VM_USE_SUDO=true
  [[ -f $LEGACY_COMPOSE_FILE || -f $CREDENTIALS_FILE ]] || return 0
  ((EUID != 0)) || {
    echo "Run Windows VM reconciliation as its owner, without sudo." >&2
    return 1
  }
  priv prepare_reconcile && migrate_legacy_compose defer && priv reconcile || return 1
  rm -f -- "$LEGACY_COMPOSE_FILE"
}

monarch_reconcile_windows_vm
