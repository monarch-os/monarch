#!/bin/bash

idle_interval=${MONARCH_UPDATE_INTERVAL:-21600} # 6h while up to date
busy_interval=600                               # 10min for pending updates or failed checks
offline_interval=60

online() {
  local connectivity
  connectivity=$(LC_ALL=C nmcli -t -f STATE,CONNECTIVITY general 2>/dev/null) || return 1
  [[ $connectivity == "connected:full" ]]
}

prev=""
while true; do
  status=offline
  if online; then
    status=0
    monarch-update-available >/dev/null 2>&1 || status=$?
    if (( status != 0 && status != 1 )) && ! online; then
      status=offline
    fi
  fi
  case $status in
    0)
      line='{"text":"","tooltip":"Monarch update available","textColor":"on_surface"}'
      interval=$busy_interval
      ;;
    1)
      line='{}'
      interval=$idle_interval
      ;;
    offline)
      line='{}'
      interval=$offline_interval
      ;;
    *)
      line='{"text":"","tooltip":"Could not check for updates. Click to check in the terminal.","textColor":"on_surface_variant"}'
      interval=$busy_interval
      ;;
  esac
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep "$interval"
done
