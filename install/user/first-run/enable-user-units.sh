#!/bin/bash

set -euo pipefail

systemctl --user daemon-reload
systemctl --user enable --now \
  monarch-crash-watch.service \
  monarch-recover-internal-monitor.service \
  monarch-obsidian-theme.path

if monarch-battery-present; then
  systemctl --user enable --now monarch-battery-monitor.timer
fi
