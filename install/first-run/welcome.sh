#!/bin/bash

# Open the Monarch welcome TUI in a floating terminal AND re-apply the Monarch
# theme once Noctalia IPC is alive (the install-time monarch-theme-apply runs
# before Noctalia is up, so its `wallpaper set` IPC silently no-ops). Both
# detached so monarch-first-run returns immediately.

# The wizard ships as its own package, which the user may have removed. Skip it
# rather than flashing an empty terminal on their first login.
if monarch-cmd-present monarch-welcome; then
  setsid --fork monarch-launch-floating-terminal-with-presentation --app-id=org.monarch.welcome monarch-welcome \
    </dev/null >/dev/null 2>&1 &
fi

setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if qs -c noctalia-shell ipc call wallpaper refresh >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  monarch-theme-apply >/dev/null 2>&1 || true
' </dev/null >/dev/null 2>&1 &
