echo "Replace Hyprland with Niri as the Monarch compositor"

# 1. Back up the existing Hyprland config directory so nothing is lost.
if [[ -d $HOME/.config/hypr ]]; then
  backup="$HOME/.config/hypr.backup-$(date +%Y%m%d%H%M%S)"
  cp -r "$HOME/.config/hypr" "$backup"
  echo "  Backed up ~/.config/hypr to $backup"
fi

# 2. Drop the Hyprland packages we no longer need.
#    Kept: hyprpicker (wlr-screencopy capture, works under any wlroots-like
#    compositor) and hyprlock (ext-session-lock-v1 client, decoupled from
#    Hyprland-the-compositor).
for pkg in hyprland hyprland-guiutils hyprland-preview-share-picker hypridle hyprsunset xdg-desktop-portal-hyprland; do
  if monarch-pkg-present "$pkg"; then
    monarch-pkg-drop "$pkg" || true
  fi
done

# 3. Install the Niri stack if any piece is missing.
for pkg in niri hyprlock swayidle wlsunset xdg-desktop-portal-gnome wtype; do
  if monarch-pkg-missing "$pkg"; then
    monarch-pkg-add "$pkg" || true
  fi
done

# 4. Deploy the new Niri / swayidle / hyprlock / wlsunset configurations.
mkdir -p "$HOME/.config/niri" "$HOME/.config/swayidle" "$HOME/.config/hyprlock" "$HOME/.config/wlsunset"
[[ -f $HOME/.config/niri/user.kdl ]] || cp "$MONARCH_PATH/config/niri/user.kdl" "$HOME/.config/niri/user.kdl"
monarch-refresh-config swayidle/config
monarch-refresh-config hyprlock/hyprlock.conf
monarch-refresh-config wlsunset/wlsunset.conf
monarch-refresh-niri || true

# 5. Restart the now-active services.
pkill -x hypridle 2>/dev/null || true
pkill -x hyprsunset 2>/dev/null || true
pkill -x swayidle 2>/dev/null || true
setsid uwsm-app -- swayidle -w -C "$HOME/.config/swayidle/config" >/dev/null 2>&1 &

# 6. Update the SDDM session and greeter compositor to point at Niri.
if [[ -f /etc/sddm.conf.d/10-wayland.conf ]]; then
  sudo sed -i 's|^CompositorCommand=start-hyprland.*|CompositorCommand=niri --config /usr/share/sddm/niri.kdl|' /etc/sddm.conf.d/10-wayland.conf
fi
if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
  sudo sed -i -e 's/^Session=hyprland-uwsm$/Session=monarch/' -e 's/^Session=niri$/Session=monarch/' /etc/sddm.conf.d/autologin.conf
fi
if [[ -f /usr/share/sddm/hyprland.conf ]]; then
  sudo rm -f /usr/share/sddm/hyprland.conf
fi
if [[ -f $MONARCH_PATH/default/sddm/niri.kdl ]]; then
  sudo cp "$MONARCH_PATH/default/sddm/niri.kdl" /usr/share/sddm/niri.kdl
fi
if [[ -f $MONARCH_PATH/default/wayland-sessions/monarch.desktop ]]; then
  sudo cp "$MONARCH_PATH/default/wayland-sessions/monarch.desktop" /usr/local/share/wayland-sessions/monarch.desktop 2>/dev/null || true
fi

# 7. If Hyprland is still the running compositor, the user must log out manually
#    to land on the new Niri session. Notify them.
if pgrep -x Hyprland >/dev/null 2>&1; then
  notify-send -u critical "Monarch is now using Niri" \
    "Hyprland was replaced by Niri. Log out of this Hyprland session and pick 'Monarch (Niri uwsm)' on the SDDM screen to enter the new compositor." \
    2>/dev/null || true
  echo
  echo "  ============================================================"
  echo "  Hyprland has been replaced by Niri."
  echo "  Log out of this session, then choose 'Monarch (Niri uwsm)'"
  echo "  in SDDM to enter the new compositor."
  echo "  Your old ~/.config/hypr was backed up to:"
  echo "  $backup"
  echo "  ============================================================"
  echo
fi
