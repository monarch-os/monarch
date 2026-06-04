#!/bin/bash

# Streaming text source for the Noctalia "screen-recording" CustomButton widget.
#
# Replaces the old Waybar custom/screenrecording-indicator (default/waybar/
# indicators/screen-recording.sh), which Noctalia has no built-in widget for.
# CustomButton runs this via `sh -lc` in textStream mode: every emitted line
# updates the widget. We print JSON (parseJson) with an `icon` while
# gpu-screen-recorder runs, and an empty object otherwise so hideMode
# "expandWithOutput" collapses the widget (no icon + no text -> hidden).
#
# Click handling lives in the widget's leftClickExec
# (monarch-capture-screenrecording, which stops the active recording).

prev="__init__"
while true; do
  if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    line='{"icon":"video","tooltip":"Stop recording","iconColor":"error"}'
  else
    line='{}'
  fi
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep 1
done
