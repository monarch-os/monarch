#!/bin/bash

notify_update() {
  monarch-notification-send -u critical -g  "Update System" "Click to update the system." \
    --exec monarch-launch-floating-terminal-with-presentation monarch-update
}

notify_wifi() {
  monarch-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." \
    --exec monarch-launch-wifi
}

announce_network() {
  nm-online -q -s -t 30
  if ! nm-online -q -x -t 30; then
    notify_wifi
    nm-online -q -t 3600 || return
  fi
  notify_update
}

announce_network &
