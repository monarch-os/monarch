echo "Install xwayland-satellite for X11 GUI app support under Niri"

# Niri ships no built-in Xwayland. Its native xwayland-satellite integration
# provides the X11 socket and exports DISPLAY once the binary is present —
# required for X11-only GUI apps such as the exegol/rfswift containers'
# firefox/bloodhound. monarch-pkg-add is a no-op when already installed.
monarch-pkg-add xwayland-satellite

# Niri only wires up Xwayland at session startup, so a running session must be
# restarted (log out and back in) before DISPLAY becomes available.
if pgrep -x niri >/dev/null 2>&1; then
  echo "Log out and back in to activate X11 support (Niri sets up Xwayland at startup)."
fi
