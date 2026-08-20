echo "Keep Wi-Fi power save off, and retire any iwd the installer left behind"

# Monarch shipped a udev rule that turned power save *on* whenever the mains
# went away. It trades 20-300ms latency spikes on an idle link for a fraction of
# a watt, and some firmware drops the link rather than waking cleanly — ath11k
# and Intel BE200/BE211 are the ones people report. Omarchy keeps it off
# unconditionally and ships no udev rule.

if [[ -f /etc/udev/rules.d/99-wifi-powersave.rules ]]; then
  echo "  Removing the rule that enabled power save on battery."
  sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
  sudo udevadm control --reload
fi

sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'CONF'
# Managed by Monarch. wifi.powersave = 2 means "disable".
[connection]
wifi.powersave = 2
CONF

sudo nmcli general reload conf >/dev/null 2>&1 || true

# NetworkManager only applies wifi.powersave when a connection activates, so
# switch it off on the running interfaces too rather than wait for a reconnect.
shopt -s nullglob
for wireless in /sys/class/net/*/wireless; do
  iface=$(basename "$(dirname "$wireless")")
  sudo iw dev "$iface" set power_save off 2>/dev/null || true
done

# Same installer path, second gift: `network_config: iso` installs and enables
# iwd when the live session joined a Wi-Fi, so a machine installed over Wi-Fi
# has been racing wpa_supplicant for the radio ever since. Migration 1781266508
# only removed iwd where the old backend config was present, which a fresh
# install never had.
if systemctl is-enabled iwd.service >/dev/null 2>&1 ||
  systemctl is-active iwd.service >/dev/null 2>&1; then
  echo "  Disabling iwd; NetworkManager drives wpa_supplicant."
  sudo systemctl disable --now iwd.service 2>/dev/null || true
fi

if monarch-pkg-present iwd && [[ ! -f /etc/NetworkManager/conf.d/wifi_backend.conf ]]; then
  monarch-pkg-drop iwd
fi
