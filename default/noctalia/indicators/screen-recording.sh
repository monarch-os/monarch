#!/bin/bash

# Streaming text source for the Noctalia "screen-recording" CustomButton widget.
#
# Replaces the old Waybar custom/screenrecording-indicator (default/waybar/
# indicators/screen-recording.sh), which Noctalia has no built-in widget for.
# CustomButton runs this via `sh -lc` in textStream mode: every emitted line
# updates the widget.
#
# Visibility must be driven by TEXT, not an icon: CustomButton's `_pillVisible`
# is `hasOutput || (showIcon && hasActualIcon)`, and `hasActualIcon` is always
# true because the widget's static icon falls back to a non-empty metadata
# default ("heart") that an empty `icon` setting can't clear. So the widget
# runs with showIcon:false and we emit a colored text indicator while
# gpu-screen-recorder runs, and an empty object otherwise — with hideMode
# "expandWithOutput", empty text (hasOutput=false) collapses the widget.
#
# Click handling lives in the widget's leftClickExec
# (monarch-capture-screenrecording, which stops the active recording).

prev="__init__"
while true; do
  if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    line='{"text":"● REC","tooltip":"Stop recording","textColor":"error"}'
  else
    line='{}'
  fi
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep 1
done
