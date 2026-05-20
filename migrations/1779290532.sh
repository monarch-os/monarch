echo "Switch Wi-Fi stack to NetworkManager with the iwd backend"

# Bring NetworkManager back; iwd stays on as its (fast) Wi-Fi backend so the
# Noctalia network widget (nmcli-only) works again.
monarch-pkg-add networkmanager

# impala drove iwd directly; with NetworkManager owning connection state it
# would only cause drift, so drop it.
if monarch-pkg-present impala; then
  monarch-pkg-drop impala
fi

# iwd handles Wi-Fi association only; NetworkManager owns IP/DHCP and profiles.
sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf >/dev/null <<'EOF'
[device]
wifi.backend=iwd
EOF

# Route DNS through systemd-resolved so monarch-setup-dns keeps working.
sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<'EOF'
[main]
dns=systemd-resolved
EOF

# NetworkManager now manages the links; stop systemd-networkd from competing.
sudo systemctl disable systemd-networkd.service 2>/dev/null || true
sudo systemctl disable systemd-networkd.socket 2>/dev/null || true

sudo systemctl enable iwd.service
sudo systemctl enable NetworkManager.service

echo "Reboot to complete the switch to NetworkManager."
