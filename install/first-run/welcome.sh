#!/bin/bash

# Open the Monarch welcome TUI in a floating terminal AND, once Noctalia IPC is
# alive, enable the bundled plugins and re-apply the Monarch theme. Both of
# those need a running shell: `plugins enable` talks to the daemon, and the
# install-time monarch-theme-apply runs before Noctalia is up, so its
# `wallpaper-set` IPC silently no-ops. `msg status` is the readiness probe — it
# fails while nothing is listening on the socket. Both detached so
# monarch-first-run returns immediately.

setsid --fork monarch-launch-floating-terminal-with-presentation monarch-welcome \
  </dev/null >/dev/null 2>&1 &

setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if noctalia msg status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  # Seeding a plugin into ~/.local/share/noctalia/plugins/ only makes Noctalia
  # discover it; installation and activation are separate, and a discovered
  # plugin stays disabled until asked for. Without this the bar indicators are
  # simply absent on a fresh install. Idempotent.
  for plugin in monarch/indicators monarch/agents monarch/menu; do
    noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || true
  done
  monarch-theme-apply >/dev/null 2>&1 || true
' </dev/null >/dev/null 2>&1 &
