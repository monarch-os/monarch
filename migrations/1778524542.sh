echo "Replace Hyprland with Niri as the Monarch compositor"

# 0. Mandatory acknowledgement. This is a one-way move off Hyprland: the
#    Hyprland packages and their Monarch wiring are removed and cannot be
#    restored automatically. Monarch is no longer maintained on Hyprland, so
#    declining leaves the system in an unsupported state that can't receive
#    further updates until the migration is applied. Exiting non-zero keeps the
#    migration pending (monarch-migrate will not mark it done) so it is offered
#    again on the next update.
cat <<'WARN'

  ============================================================
  Monarch is migrating from Hyprland to Niri.

  This change is IRREVERSIBLE. The Hyprland packages and their
  Monarch configuration wiring will be removed (your existing
  ~/.config/hypr is backed up first, but the system migration
  itself cannot be undone).

  Monarch is no longer maintained on Hyprland: until this
  migration is applied, the system cannot be kept up to date.
  ============================================================

WARN
if ! gum confirm "Proceed with the irreversible migration to Niri?"; then
  echo "  Migration to Niri declined — Monarch cannot be maintained on Hyprland until it is applied." >&2
  exit 1
fi

# 1. Back up the existing Hyprland config directory so nothing is lost.
if [[ -d $HOME/.config/hypr ]]; then
  backup="$HOME/.config/hypr.backup-$(date +%Y%m%d%H%M%S)"
  cp -r "$HOME/.config/hypr" "$backup"
  echo "  Backed up ~/.config/hypr to $backup"
fi

# 2. Drop the Hyprland packages we no longer need.
#    --cascade removes them in a single transaction together with anything that
#    still depends on them — both the known dependents (xdg-desktop-portal-hyprland
#    and hyprland-guiutils require hyprland) and any unexpected one, e.g. a
#    user-installed AUR package built against hyprland — so the removal can't be
#    aborted by a dependency it didn't anticipate.
#    Kept: hyprpicker (wlr-screencopy capture, works under any wlroots-like
#    compositor) and hyprlock (no dependency on the targets) — the latter is
#    dropped by the later Noctalia migration (1779188617) since Noctalia owns the
#    lock screen.
monarch-pkg-drop --cascade hyprland hyprland-guiutils hyprland-preview-share-picker \
  hypridle hyprsunset xdg-desktop-portal-hyprland || true

# 3. Install the Niri stack if any piece is missing.
for pkg in niri wlsunset xdg-desktop-portal-gnome wtype; do
  if monarch-pkg-missing "$pkg"; then
    monarch-pkg-add "$pkg" || true
  fi
done

# 3b. Switching compositors can't be done live — flag a reboot so the user is
#     prompted to restart into the new Niri session after the update finishes.
if monarch-pkg-present niri; then
  monarch-state set reboot-required
fi

# 4. Deploy the new Niri configuration.
#    Lock screen, night light and idle are owned by Noctalia; lid-close lock
#    lives in niri switch-events (default/niri/power.kdl). Monarch ships no
#    hyprlock / wlsunset / swayidle config.
mkdir -p "$HOME/.config/niri"
[[ -f $HOME/.config/niri/user.kdl ]] || cp "$MONARCH_PATH/config/niri/user.kdl" "$HOME/.config/niri/user.kdl"
monarch-refresh-niri || true

# 5. Stop the old Hyprland daemons (Niri + Noctalia take over).
pkill -x hypridle 2>/dev/null || true
pkill -x hyprsunset 2>/dev/null || true

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
