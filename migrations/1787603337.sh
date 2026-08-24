echo "Launch the Monarch screensaver on idle"

config="$HOME/.config/noctalia/config.toml"

if [[ -f $config ]]; then
  sed -i '/^# v4.s flat idle\./,+2c\# Named behaviours run in this order as the idle duration crosses each timeout.' "$config"

  if grep -q '^behavior_order = ' "$config" && ! grep -q '^behavior_order = .*"screensaver"' "$config"; then
    sed -i '/^behavior_order = /s/\[/["screensaver", /' "$config"
  fi

  if ! grep -q '^[[:space:]]*\[idle\.behavior\.screensaver\]$' "$config"; then
    if grep -q '^[[:space:]]*\[idle\.behavior\.lock\]$' "$config"; then
      sed -i '/^[[:space:]]*\[idle\.behavior\.lock\]$/i\
  [idle.behavior.screensaver]\
  action = "command"\
  enabled = true\
  timeout = 150.0\
  command = "monarch-launch-screensaver"\
  resume_command = "pkill -f '\''[o]rg.monarch.screensaver'\''"\
' "$config"
    else
      printf '\n  [idle.behavior.screensaver]\n  action = "command"\n  enabled = true\n  timeout = 150.0\n  command = "monarch-launch-screensaver"\n  resume_command = "pkill -f '\''[o]rg.monarch.screensaver'\''"\n' >>"$config"
    fi
  fi
fi
