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

# archinstall's `network_config: iso` copies the live installer's iwd .psk files
# into the target and installs and enables iwd with them, so any machine
# installed over Wi-Fi arrives with iwd racing wpa_supplicant for the radio.
# Monarch left that backend deliberately — it never re-associates after suspend
# on ath11k — so retire it here as well as in migration 1781266508, which only
# ever fires on an install that carried the old backend config.
sudo systemctl disable --now iwd.service 2>/dev/null || true

# NetworkManager manages the links; systemd-networkd must not compete with it.
# monarch-iso asks archinstall for `network_config: iso`, which copies the live
# ISO's networkd setup into the target — stock DHCP .network files and the
# sockets that pull networkd back up — so retire all of it, not just the service.
for unit in \
  systemd-networkd.service \
  systemd-networkd.socket \
  systemd-networkd-varlink.socket \
  systemd-networkd-varlink-metrics.socket \
  systemd-networkd-resolve-hook.socket; do
  sudo systemctl disable "$unit" 2>/dev/null || true
done

# Otherwise boot waits out its timeout on links NetworkManager owns.
sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# Only the untouched ISO copies are retired; a file the user wrote keeps its place.
networkd_backup="/etc/systemd/network/monarch-networkd-retired-$(date +%Y%m%d%H%M%S)"
for file in /etc/systemd/network/20-ethernet.network /etc/systemd/network/20-wlan.network /etc/systemd/network/20-wwan.network; do
  [[ -f $file ]] || continue
  grep -qE '^[[:space:]]*DHCP=yes[[:space:]]*$' "$file" || continue
  # Two archiso generations: older files match by Name= glob, newer by Type=.
  grep -qE '^[[:space:]]*(Name=(en|eth|wl|ww)\*|Type=(ether|wlan|wwan))[[:space:]]*$' "$file" || continue
  sudo install -d -m 0755 "$networkd_backup"
  sudo mv "$file" "$networkd_backup/"
done

# NetworkManager dbus-activates wpa_supplicant itself; the standalone service
# would race it, so leave wpa_supplicant.service disabled.
sudo systemctl enable NetworkManager.service
