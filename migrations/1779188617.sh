echo "Replace waybar/walker/mako/hyprlock/swayosd/swaybg with Noctalia desktop shell"

# 1. Stop the now-retired services so they don't fight Noctalia for layer-shell
#    real-estate during the switchover.
for proc in waybar walker elephant mako hyprlock swayosd-server swayosd-libinput-backend swaybg; do
  pkill -x "$proc" 2>/dev/null || true
done

systemctl --user disable --now swayosd-libinput-backend.service swayosd-server.service 2>/dev/null || true
systemctl --user disable --now app-walker@autostart.service 2>/dev/null || true
systemctl --user disable --now elephant.service 2>/dev/null || true

# 2. Drop the obsolete user configs and autostart entries.
for d in waybar walker hyprlock swayosd mako elephant; do
  if [[ -d $HOME/.config/$d ]]; then
    mv "$HOME/.config/$d" "$HOME/.config/$d.backup-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
done
rm -f "$HOME/.config/autostart/walker.desktop"
rm -rf "$HOME/.config/systemd/user/app-walker@autostart.service.d"
sudo rm -f /etc/pacman.d/hooks/walker-restart.hook

# 3. Install Noctalia and its supporting tooling. Falls back to AUR for
#    noctalia-shell since it has not yet landed in the Monarch repo.
for pkg in cliphist fuzzel ddcutil; do
  monarch-pkg-missing "$pkg" && monarch-pkg-add "$pkg" || true
done
if monarch-pkg-missing noctalia-shell; then
  monarch-pkg-aur-add noctalia-shell || true
fi

# 4. Remove the now-unused packages — keep installed copies if the user is
#    still relying on them outside Monarch (best-effort drop only).
for pkg in waybar omarchy-walker walker mako swaybg swayosd hyprlock; do
  if monarch-pkg-present "$pkg"; then
    monarch-pkg-drop "$pkg" 2>/dev/null || true
  fi
done

# 5. Seed the Noctalia user config and the shipped Monarch color scheme from
#    Monarch's defaults. Theming is delegated to Noctalia: a single "Monarch"
#    scheme (dark + light blocks) ships as a real file under colorschemes/.
rm -f "$HOME/.config/noctalia/colorschemes/Monarch/Monarch.json" # drop any old symlink
monarch-refresh-config noctalia/settings.json || true
monarch-refresh-config noctalia/colorschemes/Monarch/Monarch.json || true

# 6. Apply the residual system theming layer (wallpaper, Chromium, keyboard).
#    Redirect stdout so it runs non-interactively (skips the heavy Plymouth path).
monarch-cmd-present monarch-theme-apply && monarch-theme-apply >/dev/null 2>&1 || true

# 7. Refresh Niri so the new autostart/binds pick up Noctalia, then launch it
#    immediately if a Niri session is already running.
monarch-refresh-niri || true
if pgrep -x niri >/dev/null 2>&1 && ! pgrep -f 'qs.*noctalia-shell' >/dev/null 2>&1; then
  setsid uwsm-app -- qs -c noctalia-shell >/dev/null 2>&1 &
fi
