echo "Backfill Noctalia lock-screen fingerprint wiring for pre-Niri setups"

# Migration 1779363838 backfilled this, but gated on the fingerprint-enabled
# marker that the Hyprland-era setup never wrote — so pre-Niri fingerprint users
# were skipped and lost the sensor on the Noctalia lock screen. Detect via
# marker-independent signals and repair whatever is missing, idempotently.

fingerprint_present() {
  grep -q pam_fprintd.so /etc/pam.d/sudo 2>/dev/null && return 0
  grep -q pam_fprintd.so /etc/pam.d/polkit-1 2>/dev/null && return 0
  command -v fprintd-list >/dev/null && fprintd-list "$USER" 2>/dev/null | grep -q '#' && return 0
  return 1
}

if ! fingerprint_present; then
  echo "  No existing fingerprint setup detected; nothing to do."
  exit 0
fi

changed=0

# Dedicated PAM service (fingerprint first, password fallback).
if ! grep -q pam_fprintd.so /etc/pam.d/noctalia 2>/dev/null; then
  echo "  Creating /etc/pam.d/noctalia"
  sudo tee /etc/pam.d/noctalia >/dev/null <<'EOF'
#%PAM-1.0
# Managed by Monarch (monarch-setup-security-fingerprint).
# Fingerprint first, password (system-auth) as fallback.
auth      sufficient pam_fprintd.so
auth      include    system-auth
account   include    system-auth
password  include    system-auth
session   include    system-auth
EOF
  changed=1
fi

# Point Noctalia at that service.
if [[ ! -f $HOME/.config/environment.d/noctalia-fingerprint.conf ]]; then
  echo "  Writing ~/.config/environment.d/noctalia-fingerprint.conf"
  mkdir -p "$HOME/.config/environment.d"
  cat >"$HOME/.config/environment.d/noctalia-fingerprint.conf" <<'EOF'
# Managed by Monarch (monarch-setup-security-fingerprint).
# Removed by monarch-remove-security-fingerprint.
NOCTALIA_PAM_SERVICE=noctalia
EOF
  changed=1
fi

if [[ ! -f $HOME/.local/state/monarch/fingerprint-enabled ]]; then
  mkdir -p "$HOME/.local/state/monarch"
  touch "$HOME/.local/state/monarch/fingerprint-enabled"
fi

# Arm the reader at lock + keep the password fallback.
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null; then
  [[ -f $cfg ]] || { mkdir -p "$(dirname "$cfg")"; echo '{}' >"$cfg"; }
  if [[ $(jq -r '.general.autoStartAuth // false' "$cfg") != "true" ||
        $(jq -r '.general.allowPasswordWithFprintd // false' "$cfg") != "true" ]]; then
    tmp=$(mktemp)
    if jq '.general = (.general // {})
           | .general.autoStartAuth = true
           | .general.allowPasswordWithFprintd = true' "$cfg" >"$tmp"; then
      mv "$tmp" "$cfg"
      echo "  Enabled autoStartAuth + allowPasswordWithFprintd in $cfg"
      changed=1
    else
      rm -f "$tmp"
      echo -e "\e[33m  Could not update $cfg; set general.autoStartAuth manually.\e[0m"
    fi
  fi
else
  echo -e "\e[33m  jq not found; set general.autoStartAuth in $cfg manually.\e[0m"
fi

if [[ $changed -eq 0 ]]; then
  echo "  Lock-screen fingerprint wiring already complete; nothing to do."
  exit 0
fi

# Restart so Noctalia reloads the toggles instead of reverting them on logout.
if command -v monarch-restart-noctalia >/dev/null && pgrep -f 'qs.*noctalia-shell' >/dev/null 2>&1; then
  echo "  Restarting Noctalia so the lock screen picks up the change"
  monarch-restart-noctalia
fi

echo "  Done. Log out and back in so the lock screen inherits NOCTALIA_PAM_SERVICE."
