echo "Silence Noctalia's first-run Privacy Update + Changelog popups"

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

# 2. Seed shell-state.json with the installed Noctalia version so the telemetry
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
