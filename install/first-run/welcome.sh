#!/bin/bash

# Open the Monarch welcome TUI in a floating terminal (with the Monarch
# presentation wrapper: logo + done banner). Detached so monarch-first-run
# returns immediately.

setsid --fork monarch-launch-floating-terminal-with-presentation monarch-welcome \
  </dev/null >/dev/null 2>&1 &
