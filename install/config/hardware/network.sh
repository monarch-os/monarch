# Wi-Fi runs through NetworkManager with its default wpa_supplicant backend.
# NetworkManager owns connections, IP and profiles so the Noctalia network
# widget (which only speaks nmcli) works; DNS stays on systemd-resolved.
#
# Monarch previously used iwd as NetworkManager's Wi-Fi backend, but the
# NetworkManager<->iwd integration fails to re-associate after suspend on some
# chipsets (notably Qualcomm ath11k): iwd stays `disconnected` on resume until
# NetworkManager is restarted by hand. NetworkManager drives wpa_supplicant
# directly and recovers from suspend reliably, so we use it instead.

sudo mkdir -p /etc/NetworkManager/conf.d

# Route DNS through systemd-resolved so `monarch-setup-dns` keeps working.
sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<'EOF'
[main]
dns=systemd-resolved
EOF

# NetworkManager manages the links; systemd-networkd must not compete with it.
sudo systemctl disable systemd-networkd.service 2>/dev/null || true

# NetworkManager dbus-activates wpa_supplicant itself; the standalone service
# would race it, so leave wpa_supplicant.service disabled.
sudo systemctl enable NetworkManager.service
