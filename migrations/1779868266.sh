echo "Silence Noctalia's first-run Privacy Update + Changelog popups; re-apply Monarch wallpaper"

# 1. Merge `general.showChangelogOnStartup = false` into the user's settings.json
#    (Noctalia hot-reloads on file change).
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f $cfg ]]; then
  tmp=$(mktemp)
  if jq '.general = (.general // {}) | .general.showChangelogOnStartup = false' "$cfg" >"$tmp"; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"
  fi
fi

# 2. Stop Noctalia BEFORE touching shell-state.json so the running instance
#    doesn't rewrite it from its in-memory state right after our seed.
pkill -f 'qs.*noctalia-shell' 2>/dev/null || true
for _ in $(seq 1 30); do
  pgrep -f 'qs.*noctalia-shell' >/dev/null 2>&1 || break
  sleep 0.1
done

# 3. Seed shell-state.json with the installed Noctalia version so the telemetry
#    wizard (gated on lastSeenVersion >= 4.0.2) never triggers.
state_file="$HOME/.cache/noctalia/shell-state.json"
mkdir -p "$(dirname "$state_file")"
[[ -f $state_file ]] || echo '{}' >"$state_file"

ver=$(pacman -Q noctalia-shell 2>/dev/null | awk '{print $2}' | cut -d- -f1)
[[ -z $ver ]] && ver="4.0.2"

if command -v jq >/dev/null; then
  tmp=$(mktemp)
  if jq --arg v "$ver" '.changelogState = ((.changelogState // {}) | .lastSeenVersion = $v)' \
       "$state_file" >"$tmp"; then
    mv "$tmp" "$state_file"
  else
    rm -f "$tmp"
  fi
fi

# 4. Start Noctalia back up.
setsid uwsm-app -- qs -c noctalia-shell >/dev/null 2>&1 &

# 5. After Noctalia is up, re-apply the Monarch theme so the wallpaper IPC
#    actually lands (install-time monarch-theme-apply runs before Noctalia is
#    alive, so the IPC silently fails; this catches up).
setsid --fork bash -c '
  for _ in $(seq 1 30); do
    if qs -c noctalia-shell ipc call wallpaper refresh >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  monarch-theme-apply >/dev/null 2>&1 || true
' </dev/null >/dev/null 2>&1 &
