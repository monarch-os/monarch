#!/bin/bash

# Streaming text source for the Noctalia "screen-recording" bar indicator.
#
# Replaces the old Waybar custom/screenrecording-indicator (default/waybar/
# indicators/screen-recording.sh), which Noctalia has no built-in widget for.
# The monarch-indicators plugin runs this through indicator.luau's runStream and
# maps each emitted line onto the widget.
#
# Visibility is driven by TEXT: we emit a colored indicator while
# gpu-screen-recorder runs, and an empty object otherwise, which the plugin
# turns into setVisible(false). (In v4 this was a hard constraint rather than a
# convention — CustomButton's pill stayed visible for any icon it could fall
# back to, so text was the only thing that could collapse it.)
#
# Click handling lives in the widget's leftClickExec
# (monarch-capture-screenrecording, which stops the active recording).

# The glyph matches Omarchy's ScreenRecording indicator (shell/plugins/bar/
# indicators/ScreenRecording.qml), which renders 󰻂 with a "Stop recording"
# tooltip rather than a text badge. Its visibility rule is the same as ours:
# the indicator is only on screen while a recording runs.
prev="__init__"
while true; do
  if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    line='{"text":"󰻂","tooltip":"Stop recording","textColor":"error"}'
  else
    line='{}'
  fi
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep 1
done
