#!/bin/bash

# Streaming text source for the Noctalia "monarch-update" bar indicator.
#
# Faithful port of the old Waybar custom/update module (removed with the
# Noctalia switchover): show a glyph when a newer Monarch release is available,
# click to run the updater. The monarch-indicators plugin runs this through
# indicator.luau's runStream and maps each emitted line onto the widget. As with
# the screen-recording indicator, visibility is driven by TEXT: an empty object
# hides the widget when there is nothing to update.
#
# Availability comes from monarch-update-available (live `git ls-remote` tag
# compare, exit 0 = update available). Waybar polled this every 6h and relied
# on a SIGRTMIN+7 from monarch-update-available-reset to clear the badge
# instantly after an update; a Noctalia stream can't take a signal, so instead
# we recheck quickly WHILE the badge is shown — it clears soon after the user
# updates — and fall back to the 6h cadence once up to date.
#
# Click handling lives in the widget's leftClickExec
# (monarch-launch-floating-terminal-with-presentation monarch-update).

idle_interval=${MONARCH_UPDATE_INTERVAL:-21600} # 6h while up to date
busy_interval=600                               # 10min while the badge is shown

prev="__init__"
while true; do
  if monarch-update-available >/dev/null 2>&1; then
    line='{"text":"","tooltip":"Monarch update available"}'
    interval=$busy_interval
  else
    line='{}'
    interval=$idle_interval
  fi
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep "$interval"
done
