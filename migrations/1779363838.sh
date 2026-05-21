echo "Wire fingerprint auth into the Noctalia lock screen for existing installs"

# The monarch-setup-security-fingerprint rewrite now also wires Noctalia's lock
# screen (dedicated PAM service + env var + settings flags). New setups get this
# for free, but users who enabled fingerprint auth earlier never re-run that
# script: their sudo/polkit fingerprint keeps working while the Noctalia lock
# screen silently has no sensor. This migration backfills the wiring for them.
MARKER="$HOME/.local/state/monarch/fingerprint-enabled"
if [[ ! -f $MARKER ]]; then
  echo "  Fingerprint auth not enabled here; nothing to do."
  exit 0
fi

# 1. Dedicated PAM service for Noctalia (fingerprint first, password fallback).
#    Kept out of system-auth so sudo isn't exposed to CVE-2024-37408 background
#    fingerprint hijacking.
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
fi

# 2. Point Noctalia at that service. environment.d is read by the systemd user
#    manager at login, so the uwsm-launched shell inherits it.
if [[ ! -f $HOME/.config/environment.d/noctalia-fingerprint.conf ]]; then
  echo "  Writing ~/.config/environment.d/noctalia-fingerprint.conf"
  mkdir -p "$HOME/.config/environment.d"
  cat >"$HOME/.config/environment.d/noctalia-fingerprint.conf" <<'EOF'
# Managed by Monarch (monarch-setup-security-fingerprint).
# Removed by monarch-remove-security-fingerprint.
NOCTALIA_PAM_SERVICE=noctalia
EOF
fi

# 3. Arm the reader the moment the lock screen appears (autoStartAuth) and keep
#    the password fallback alongside fprintd. Without autoStartAuth, Noctalia
#    only invokes PAM once you start typing, so a finger tap does nothing.
cfg="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null; then
  [[ -f $cfg ]] || { mkdir -p "$(dirname "$cfg")"; echo '{}' >"$cfg"; }
  tmp=$(mktemp)
  if jq '.general = (.general // {})
         | .general.autoStartAuth = true
         | .general.allowPasswordWithFprintd = true' "$cfg" >"$tmp"; then
    mv "$tmp" "$cfg"
    echo "  Enabled autoStartAuth + allowPasswordWithFprintd in $cfg"
  else
    rm -f "$tmp"
    echo -e "\e[33m  Could not update $cfg; set general.autoStartAuth manually.\e[0m"
  fi
else
  echo -e "\e[33m  jq not found; set general.autoStartAuth in $cfg manually.\e[0m"
fi

echo "  Done. Log out and back in so the lock screen picks up the fingerprint reader."
