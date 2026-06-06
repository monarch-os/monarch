echo "Make notifications compact with Mako-like timeouts (5s low/normal; critical stays persistent via respectExpireTimeout)"

# Bring existing installs in line with the new Monarch notification defaults:
# compact density + 5s timeouts (matching the old Mako default-timeout=5000).
# Critical notifications stay persistent because apps send expireTimeout=0 and
# respectExpireTimeout honours it (returns -1 / never expire), as Mako did.
# Noctalia hot-reloads settings.json on change, so no restart is needed.
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f $cfg ]]; then
  tmp=$(mktemp)
  if jq '
        .notifications = (.notifications // {})
        | .notifications.density = "compact"
        | .notifications.lowUrgencyDuration = 5
        | .notifications.normalUrgencyDuration = 5
        | .notifications.respectExpireTimeout = true
      ' "$cfg" >"$tmp"; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"
  fi
fi
