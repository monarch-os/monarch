#!/bin/bash

idle_interval=${MONARCH_UPDATE_INTERVAL:-21600} # 6h while up to date
busy_interval=600                               # 10min for pending updates or failed checks

prev=""
while true; do
  status=0
  monarch-update-available >/dev/null 2>&1 || status=$?
  case $status in
    0)
      line='{"text":"","tooltip":"Monarch update available"}'
      interval=$busy_interval
      ;;
    1)
      line='{}'
      interval=$idle_interval
      ;;
    *)
      # A failed refresh cannot invalidate the last successful availability check.
      line=$prev
      [[ -n $line ]] || line='{}'
      interval=$busy_interval
      ;;
  esac
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep "$interval"
done
