pci_info=$(lspci -nn)

if grep -q "106b:180[12]" <<<"$pci_info"; then
  echo "Detected MacBook with T2 chip. Installing support items..."

  monarch-pkg-add \
    apple-t2-audio-config \
    t2fanrd \
    tiny-dfr

  echo "T2 Wi-Fi firmware is not bundled; install apple-bcm-firmware separately."

  sudo usermod -aG video "$USER"
  sudo systemctl enable t2fanrd.service
  sudo systemctl enable tiny-dfr.service

  echo "hci_bcm4377" | sudo tee /etc/modules-load.d/t2.conf >/dev/null

  # Optional names bridge CachyOS's Linux 7.2 transition from apple-bce to t2bce.
  echo "MODULES+=(apple-bce? t2bce_dma? t2bce_core? t2bce_vhci? usbhid hid_apple hid_generic xhci_pci xhci_hcd)" |
    sudo tee /etc/mkinitcpio.conf.d/apple-t2.conf >/dev/null

  cat <<'EOF' | sudo tee /etc/modprobe.d/brcmfmac.conf >/dev/null
# Fix for T2 MacBook WiFi connectivity issues
options brcmfmac feature_disable=0x82000
EOF

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<'EOF' | sudo tee /etc/limine-entry-tool.d/t2-mac.conf >/dev/null
KERNEL_CMDLINE[default]+=" intel_iommu=on iommu=pt pm_async=off pcie_ports=compat"
EOF

  cat <<'EOF' | sudo tee /etc/t2fand.conf >/dev/null
[Fan1]
low_temp=55
high_temp=75
speed_curve=linear
always_full_speed=false
EOF
fi
