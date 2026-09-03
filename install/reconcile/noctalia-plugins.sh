#!/bin/bash

runtime=${MONARCH_PATH:-/usr/share/monarch}
source "$runtime/install/reconcile/noctalia-wait.sh"

monarch_noctalia_wait || exit 0

for plugin in monarch/indicators monarch/agents monarch/menu monarch/wifi-qr monarch/network monarch/display monarch/theme; do
  noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || exit 0
done

rm -f "$0"
"${MONARCH_RECONCILE_BIN:-/usr/bin/monarch-reconcile}" --complete
