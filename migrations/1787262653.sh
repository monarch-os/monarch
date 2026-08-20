echo "Keep Wi-Fi power save off, and retire any iwd the installer left behind"

# The rule below switched power save *on* on battery: latency spikes on an idle
# link, and some firmware drops it outright, for a fraction of a watt.

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

# The setting only lands on activation, so do the running interfaces now.
shopt -s nullglob
for wireless in /sys/class/net/*/wireless; do
  iface=$(basename "$(dirname "$wireless")")
  sudo iw dev "$iface" set power_save off 2>/dev/null || true
done

# Defensive: `network_config: iso` enables iwd when the live session left .psk
# files. Monarch installs offline, so this is cold unless someone ran iwctl.
if systemctl is-enabled iwd.service >/dev/null 2>&1 ||
  systemctl is-active iwd.service >/dev/null 2>&1; then
  echo "  Disabling iwd; NetworkManager drives wpa_supplicant."
  sudo systemctl disable --now iwd.service 2>/dev/null || true
fi

if monarch-pkg-present iwd && [[ ! -f /etc/NetworkManager/conf.d/wifi_backend.conf ]]; then
  monarch-pkg-drop iwd
fi
