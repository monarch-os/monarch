#!/bin/bash

# Streaming text source for the Noctalia "voxtype" CustomButton widget.
#
# Faithful port of the old Waybar custom/voxtype module (removed with the
# Noctalia switchover): show a dictation glyph whose shape tracks Voxtype's
# state, left-click to pick the AI model, right-click to edit the config.
# CustomButton runs this via `sh -lc` in textStream mode; every emitted line
# (parseJson) updates the widget.
#
# Voxtype is an optional, install-on-demand feature, so the indicator only
# appears once `voxtype` is present (monarch-cmd-present) — exactly like the
# old Waybar exec, which emitted an empty object otherwise. With hideMode
# "expandWithOutput" that empty object collapses the widget.
#
# When present, `voxtype status --follow --extended --format json` streams one
# line per state change with .class (idle|recording|transcribing) and a ready
# .tooltip. Waybar mapped .class -> glyph via format-icons; Noctalia has no
# such mapping, so we resolve the glyph here and emit {text,tooltip}. The idle
# mic stays visible (as in Waybar) so the click actions are always reachable.
# `trap kill 0` tears down the `--follow` child when Noctalia restarts the stream.
#
# Click handling lives in the widget's leftClickExec (monarch-voxtype-model)
# and rightClickExec (monarch-voxtype-config), matching the old on-click /
# on-click-right.

trap 'kill 0' EXIT

declare -A icons=([idle]="" [recording]="󰍬" [transcribing]="󰔟")

if ! monarch-cmd-present voxtype; then
  echo '{}'
  exit 0
fi

voxtype status --follow --extended --format json | while read -r line; do
  class=$(jq -r '.class // "idle"' <<<"$line")
  tooltip=$(jq -r '.tooltip // ""' <<<"$line")
  jq -nc --arg t "${icons[$class]:-${icons[idle]}}" --arg tip "$tooltip" '{text:$t, tooltip:$tip}'
done
