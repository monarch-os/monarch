if lspci | grep -qi 'nvidia'; then
  if monarch-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    GPU_ARCH="turing_plus"
  elif monarch-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    GPU_ARCH="maxwell_pascal_volta"
  fi
  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  # The offline mirror no longer carries the pre-Turing driver, and install.sh
  # traps ERR: without this the whole install would abort on those cards. Leave
  # before the modprobe and mkinitcpio blocks — MODULES+=(nvidia ...) against an
  # absent module builds a broken initramfs.
  if ! monarch-pkg-add $(monarch-hw-kernel-headers) "${PACKAGES[@]}"; then
    echo "NVIDIA driver unavailable. Install it later: monarch pkg add ${PACKAGES[*]}"
    exit 0
  fi

  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia_drm modeset=1
EOF

  # Configure mkinitcpio for early loading
  sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<EOF >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

  # Add NVIDIA environment variables based on GPU architecture.
  # systemd's environment.d propagates these to every user-session child,
  # so uwsm/niri and all spawned apps inherit them — no compositor-specific
  # config needed.
  mkdir -p "$HOME/.config/environment.d"
  ENV_FILE="$HOME/.config/environment.d/nvidia.conf"
  if [[ $GPU_ARCH = "turing_plus" ]]; then
    cat >"$ENV_FILE" <<'EOF'
# NVIDIA (Turing+ with GSP firmware) — managed by monarch nvidia.sh
NVD_BACKEND=direct
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  elif [[ $GPU_ARCH = "maxwell_pascal_volta" ]]; then
    cat >"$ENV_FILE" <<'EOF'
# NVIDIA (Maxwell/Pascal/Volta without GSP firmware) — managed by monarch nvidia.sh
NVD_BACKEND=egl
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  fi
fi
