echo "Drop the v4 lock-screen PAM service, which Noctalia v5 never reads"

# v5 authenticates the lock screen against the "login" stack, hardcoded, and
# never reads NOCTALIA_PAM_SERVICE. Both files below are inert, and an inert
# /etc/pam.d/noctalia still includes system-auth behind pam_fprintd.
# lockscreen.fingerprint in monarch-fingerprint.toml is what arms the reader.

if [[ -f /etc/pam.d/noctalia ]]; then
  echo "  Removing /etc/pam.d/noctalia"
  sudo rm -f /etc/pam.d/noctalia
fi

if [[ -f $HOME/.config/environment.d/noctalia-fingerprint.conf ]]; then
  echo "  Removing ~/.config/environment.d/noctalia-fingerprint.conf"
  rm -f "$HOME/.config/environment.d/noctalia-fingerprint.conf"
fi
