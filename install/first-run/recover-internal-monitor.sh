# Enable the laptop-display recovery watcher, but only on machines that have an
# internal panel (eDP) — desktops have nothing to recover.
if compgen -G "/sys/class/drm/*-eDP-*" >/dev/null; then
  systemctl --user enable --now monarch-recover-internal-monitor.service
fi
