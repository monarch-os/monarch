#!/bin/bash

# Open the Monarch welcome panel (Noctalia plugin: monarch-welcome). Retries
# in the background while noctalia-shell IPC comes up on first boot, so the
# parent monarch-first-run is never blocked.

setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if qs -c noctalia-shell ipc call plugin:monarch-welcome open >/dev/null 2>&1; then
      exit 0
    fi
    sleep 1
  done
' </dev/null >/dev/null 2>&1 &
