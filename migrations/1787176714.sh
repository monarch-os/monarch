echo "Drop the v4 lock-screen PAM service, which Noctalia v5 never reads"

# v4's lock screen took its PAM service from NOCTALIA_PAM_SERVICE, so
# monarch-setup-security-fingerprint (and migrations 1779363838 / 1780785575)
# gave it a dedicated /etc/pam.d/noctalia and pointed it there through
# environment.d. v5 has neither: the lock screen authenticates against the
# "login" stack — hardcoded, with pam_fprintd stripped, since it drives the
# reader itself over D-Bus — and the variable is gone from its source entirely.
#
# Both files are therefore inert on a v5 install, and inert PAM services are
# worth removing rather than leaving: /etc/pam.d/noctalia includes system-auth
# behind pam_fprintd, so anything that ever asked PAM for a service by that name
# would authenticate against it.
#
# What actually arms the reader on the lock screen — lockscreen.fingerprint in
# ~/.config/noctalia/monarch-fingerprint.toml — is untouched.

if [[ -f /etc/pam.d/noctalia ]]; then
  echo "  Removing /etc/pam.d/noctalia"
  sudo rm -f /etc/pam.d/noctalia
fi

if [[ -f $HOME/.config/environment.d/noctalia-fingerprint.conf ]]; then
  echo "  Removing ~/.config/environment.d/noctalia-fingerprint.conf"
  rm -f "$HOME/.config/environment.d/noctalia-fingerprint.conf"
fi
