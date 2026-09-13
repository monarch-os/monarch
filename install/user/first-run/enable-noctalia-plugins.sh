#!/bin/bash

set -euo pipefail

source "$MONARCH_PATH/install/reconcile/noctalia-activation.sh"

monarch_noctalia_wait 600 || {
  echo "Noctalia did not become ready for plugin activation" >&2
  exit 1
}

monarch_noctalia_enable_plugins
