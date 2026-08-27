#!/bin/bash

# Open the Monarch welcome TUI in a floating terminal and re-apply the theme
# once Noctalia IPC is alive. Plugin activation is a separate, verified
# first-run step; this script only owns presentation.

# The wizard ships as its own package, which the user may have removed. Skip it
# rather than flashing an empty terminal on their first login.
if monarch-cmd-present monarch-welcome; then
  setsid --fork monarch-launch-floating-terminal-with-presentation --app-id=org.monarch.welcome monarch-welcome \
    </dev/null >/dev/null 2>&1 &
fi

setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if noctalia msg status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  monarch-theme-apply >/dev/null 2>&1 || true
' </dev/null >/dev/null 2>&1 &
