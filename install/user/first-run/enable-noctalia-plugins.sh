#!/bin/bash

set -euo pipefail

source "$MONARCH_PATH/install/reconcile/noctalia-activation.sh"
source "$MONARCH_PATH/install/reconcile/config-files.sh"
source "$MONARCH_PATH/install/reconcile/codexbar.sh"
plugins_changed=false
monarch_reconcile_codexbar

monarch_noctalia_wait 600 || {
  echo "Noctalia did not become ready for plugin activation" >&2
  exit 1
}

monarch_noctalia_enable_plugins
