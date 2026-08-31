#!/bin/bash

setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if noctalia msg status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  monarch-theme-apply >/dev/null 2>&1 || true
' </dev/null >/dev/null 2>&1 &
