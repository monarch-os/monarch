echo "Migrate idle handling from swayidle to Noctalia + niri lid switch-events"

# 1. Stop and remove swayidle. Idle (screensaver / lock / DPMS) is now Noctalia's
#    IdleService; lid-close lock is a niri switch-event (default/niri/power.kdl).
pkill -x swayidle 2>/dev/null || true
if monarch-pkg-present swayidle; then
  monarch-pkg-drop swayidle || true
fi
rm -f "$HOME/.config/swayidle/config"
rmdir "$HOME/.config/swayidle" 2>/dev/null || true

# 2. Merge the idle block into the user's Noctalia settings (hot-reloaded).
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f $cfg ]]; then
  tmp=$(mktemp)
  if jq '.idle = (.idle // {})
         | .idle.enabled = true
         | .idle.lockTimeout = 300
         | .idle.screenOffTimeout = 330
         | .idle.suspendTimeout = 0
         | .idle.fadeDuration = 5
         | .idle.lockCommand = "MONARCH_LOCK_ONLY=true monarch-system-lock"
         | .idle.screenOffCommand = "monarch-brightness-keyboard off"
         | .idle.resumeScreenOffCommand = "monarch-system-wake"
         | .idle.customCommands = "[{\"timeout\":150,\"command\":\"monarch-launch-screensaver\",\"resumeCommand\":\"\"}]"' \
       "$cfg" >"$tmp"; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"
    echo "  Warning: could not update $cfg; set the idle block manually." >&2
  fi
fi

# 3. Redeploy the Niri config (brings in the lid-close switch-events and the
#    autostart without swayidle).
monarch-refresh-niri || true
