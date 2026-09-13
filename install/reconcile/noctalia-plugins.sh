#!/bin/bash

runtime=${MONARCH_PATH:-/usr/share/monarch}
source "$runtime/install/reconcile/noctalia-activation.sh"

monarch_noctalia_wait || exit 0

monarch_noctalia_enable_plugins >/dev/null 2>&1 || exit 0

rm -f "$0"
"${MONARCH_RECONCILE_BIN:-/usr/bin/monarch-reconcile}" --complete
