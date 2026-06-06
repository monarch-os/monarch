# Wi-Fi runs through iwd, but NetworkManager owns connections, IP and profiles
# so the Noctalia network widget (which only speaks nmcli) works. iwd is used
# purely as NetworkManager's Wi-Fi backend; DNS stays on systemd-resolved.

sudo mkdir -p /etc/NetworkManager/conf.d

# Use iwd for Wi-Fi association/roaming instead of wpa_supplicant.
sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf >/dev/null <<'EOF'
[device]
wifi.backend=iwd
EOF

# Route DNS through systemd-resolved so `monarch-setup-dns` keeps working.
sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<'EOF'
[main]
dns=systemd-resolved
EOF

# NetworkManager manages the links; systemd-networkd must not compete with it.
sudo systemctl disable systemd-networkd.service 2>/dev/null || true

# iwd is NetworkManager's Wi-Fi backend, so wpa_supplicant must not also drive the
# radio — a second supplicant just races iwd and breaks the connection (flapping,
# "connection failed" in the Noctalia widget while association itself looks fine).
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true

sudo systemctl enable iwd.service
sudo systemctl enable NetworkManager.service
