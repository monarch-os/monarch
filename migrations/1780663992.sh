echo "Set up niri laptop-display: recovery watcher + wl-mirror for display mirroring"

# Migration 1778589348 disabled and removed the Hyprland-era oneshot of the same
# name on the premise that "niri handles hot-plug natively". It does not:
# monarch-niri-monitor-internal disables the eDP panel via a live
# `niri msg output <eDP> off` that niri never persists nor restores, so unplugging
# the external monitor mid-session leaves the laptop with no display. Re-deploy
# the service — now a long-running watcher (monarch-hw-recover-internal-monitor)
# instead of the old login oneshot — and enable it. That cleanup already runs
# before this migration, so the old enablement (symlink + unit) is gone and the
# same-named unit redeploys onto a clean slate; nothing to decommission here.
#
# Only enable it on machines that actually have an internal panel (eDP) — a
# desktop has nothing to recover. config/* is only copied on a fresh install, so
# updating installs need the unit copied here before it can be enabled.

SERVICE=monarch-recover-internal-monitor.service

if compgen -G "/sys/class/drm/*-eDP-*" >/dev/null; then
  mkdir -p ~/.config/systemd/user
  cp "$MONARCH_PATH/config/systemd/user/$SERVICE" ~/.config/systemd/user/$SERVICE
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE"

  # Laptop-display mirroring (Mod+Ctrl+Alt+Delete -> monarch-niri-monitor-internal-mirror):
  # niri has no native output mirroring, so we use wl-mirror to screencopy the eDP
  # panel fullscreen onto the external monitor. It's only useful with an internal
  # panel to mirror, so it rides the same eDP gate. config/* package lists are only
  # consumed on a fresh install, so updating installs need it pulled in here.
  monarch-pkg-missing wl-mirror && monarch-pkg-add wl-mirror || true
else
  echo "No internal (eDP) panel detected. Skipping."
fi
