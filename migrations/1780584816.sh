echo "Add the screen-recording indicator (CustomButton) to the Noctalia bar"

# Waybar had a custom/screenrecording-indicator (icon while recording, click to
# stop). The Noctalia switch dropped it and Noctalia ships no built-in widget
# for it, so new installs get a CustomButton in config/noctalia/settings.json.
# Existing niri installs never re-seed that file (Noctalia owns it after first
# run), so merge the widget into their live settings.json. Noctalia hot-reloads
# on file change; the indicator script ships in $MONARCH_PATH and is already in
# place after the update that brought this migration.

cfg="$HOME/.config/noctalia/settings.json"
[[ -f $cfg ]] || exit 0
command -v jq >/dev/null || exit 0

read -r -d '' widget <<'JSON'
{
  "id": "CustomButton",
  "textCommand": "$MONARCH_PATH/default/noctalia/indicators/screen-recording.sh",
  "textStream": true,
  "parseJson": true,
  "hideMode": "expandWithOutput",
  "showIcon": true,
  "showExecTooltip": false,
  "leftClickExec": "monarch-capture-screenrecording"
}
JSON

tmp=$(mktemp)
if jq --argjson w "$widget" '
      .bar = (.bar // {})
      | .bar.widgets = (.bar.widgets // {})
      | .bar.widgets.center = (.bar.widgets.center // [])
      | if (.bar.widgets.center | any(.id == "CustomButton"
            and ((.textCommand // "") | test("screen-recording"))))
        then .
        else .bar.widgets.center += [$w]
        end' "$cfg" >"$tmp"; then
  mv "$tmp" "$cfg"
else
  rm -f "$tmp"
  echo "  Warning: could not update $cfg; add the CustomButton widget manually." >&2
fi
