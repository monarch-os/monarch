#!/bin/bash

set -euo pipefail

for _ in $(seq 1 60); do
  noctalia msg status >/dev/null 2>&1 && break
  sleep 1
done

noctalia msg status >/dev/null 2>&1 || {
  echo "Noctalia did not become ready for plugin activation" >&2
  exit 1
}

for plugin_id in \
  monarch/indicators \
  monarch/agents \
  monarch/menu \
  monarch/wifi-qr \
  monarch/network \
  monarch/display \
  monarch/theme; do
  noctalia msg plugins enable "$plugin_id"
done

noctalia msg config-reload
