echo "Clean up Hyprland-era artefacts after Niri migration"

# 1. Disable + remove the recover-internal-monitor systemd unit. The feature
#    only made sense in tandem with monarch-hyprland-monitor-internal (deleted);
#    Niri handles hot-plug natively.
SERVICE=monarch-recover-internal-monitor.service
if systemctl --user is-enabled "$SERVICE" >/dev/null 2>&1; then
  systemctl --user disable --now "$SERVICE" 2>/dev/null || true
fi
rm -f "$HOME/.config/systemd/user/$SERVICE"
rmdir "$HOME/.local/state/monarch/toggles/hypr" 2>/dev/null || true

# 2. Move NVIDIA env vars from the legacy ~/.config/hypr/envs.conf (backed up
#    by the earlier Niri migration) to systemd's environment.d, where uwsm
#    and every user-session child can see them.
if [[ ! -f $HOME/.config/environment.d/nvidia.conf ]] && lspci 2>/dev/null | grep -qi 'nvidia'; then
  ARCH=""
  if command -v monarch-hw-nvidia-gsp >/dev/null 2>&1 && monarch-hw-nvidia-gsp; then
    ARCH="turing_plus"
  elif command -v monarch-hw-nvidia-without-gsp >/dev/null 2>&1 && monarch-hw-nvidia-without-gsp; then
    ARCH="maxwell_pascal_volta"
  fi
  if [[ -n $ARCH ]]; then
    mkdir -p "$HOME/.config/environment.d"
    ENV_FILE="$HOME/.config/environment.d/nvidia.conf"
    if [[ $ARCH = "turing_plus" ]]; then
      cat >"$ENV_FILE" <<'EOF'
# NVIDIA (Turing+ with GSP firmware) — managed by monarch nvidia.sh
NVD_BACKEND=direct
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
    else
      cat >"$ENV_FILE" <<'EOF'
# NVIDIA (Maxwell/Pascal/Volta without GSP firmware) — managed by monarch nvidia.sh
NVD_BACKEND=egl
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
    fi
    echo "  Wrote $ENV_FILE — log out and back in for it to take effect."
  fi
fi

# 3. If a legacy lazyvpn Hyprland binding survived in a backed-up hypr config,
#    no action needed — the user can reinstall monarch-lazyvpn to get the new
#    Niri binding via ~/.config/niri/user.kdl.
