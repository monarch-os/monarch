#!/bin/bash

for _ in $(seq 1 300); do
  noctalia msg status >/dev/null 2>&1 && break
  sleep 0.1
done

noctalia msg status >/dev/null 2>&1 || exit 0

for plugin in monarch/indicators monarch/agents monarch/menu monarch/wifi-qr monarch/network monarch/display monarch/theme; do
  noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || exit 0
done

rm -f "$0"
"${MONARCH_RECONCILE_BIN:-/usr/bin/monarch-reconcile}" --complete
