echo "Install the monarch-agents Noctalia plugin and add its bar widget"

# Fresh installs get all of this from config/ (plugins.json ships the plugin
# enabled and settings.json carries its bar widget). Existing installs keep
# their own copies of both files, so merge the pieces in here rather than
# overwriting and losing the user's other plugins and bar layout.

plugin_src="$MONARCH_PATH/config/noctalia/plugins/monarch-agents"
plugin_dst="$HOME/.config/noctalia/plugins/monarch-agents"

if [[ -d $plugin_src ]]; then
  mkdir -p "$plugin_dst"
  cp -rf "$plugin_src"/. "$plugin_dst/"
fi

if monarch-cmd-missing jq; then
  echo "jq missing, skipping the Noctalia wiring"
  return 0 2>/dev/null || exit 0
fi

# Enable the plugin without disturbing any other plugin state.
plugins_file="$HOME/.config/noctalia/plugins.json"
if [[ -f $plugins_file ]]; then
  tmp=$(mktemp)
  if jq '.states = ((.states // {}) | .["monarch-agents"] = ((.["monarch-agents"] // {}) | .enabled = true))' \
       "$plugins_file" >"$tmp"; then
    mv "$tmp" "$plugins_file"
  else
    rm -f "$tmp"
  fi
fi

# Add the bar widget, and drop the CustomButton indicator that an earlier
# revision of this feature used — both would show the same percentage.
settings_file="$HOME/.config/noctalia/settings.json"
if [[ -f $settings_file ]]; then
  tmp=$(mktemp)
  if jq '.bar.widgets.center = ((.bar.widgets.center // [])
           | map(select(((.textCommand? // "") | test("indicators/agents.sh")) | not)))
         | .bar.widgets.right = (
             (.bar.widgets.right // []) as $w
             | if ($w | map(.id == "plugin:monarch-agents") | index(true)) != null
               then $w
               else
                 ($w | map(.id == "Tray") | index(true)) as $i
                 | if $i == null then [{ "id": "plugin:monarch-agents" }] + $w
                   else $w[0:$i + 1] + [{ "id": "plugin:monarch-agents" }] + $w[$i + 1:]
                   end
               end
           )' "$settings_file" >"$tmp"; then
    mv "$tmp" "$settings_file"
    chmod 600 "$settings_file"
  else
    rm -f "$tmp"
  fi
fi
