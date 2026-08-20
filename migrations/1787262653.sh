echo "Keep Wi-Fi power save off, and retire any iwd the installer left behind"

# Monarch shipped a udev rule that turned power save *on* whenever the mains
# went away — latency spikes on an idle link for a fraction of a watt, and some
# firmware drops the link rather than waking cleanly.

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

# wifi.powersave only lands when a connection activates; do the running
# interfaces now rather than wait for a reconnect.
shopt -s nullglob
for wireless in /sys/class/net/*/wireless; do
  iface=$(basename "$(dirname "$wireless")")
  sudo iw dev "$iface" set power_save off 2>/dev/null || true
done

# Defensive: archinstall's `network_config: iso` installs and enables iwd when
# the live session left .psk files behind. Monarch installs offline so that
# never happens on the supported path — but nothing retires iwd if someone ran
# iwctl by hand, and 1781266508 only covered installs carrying the old backend
# config. Guarded on that same config, so a deliberate iwd setup is left alone.
if systemctl is-enabled iwd.service >/dev/null 2>&1 ||
  systemctl is-active iwd.service >/dev/null 2>&1; then
  echo "  Disabling iwd; NetworkManager drives wpa_supplicant."
  sudo systemctl disable --now iwd.service 2>/dev/null || true
fi

if monarch-pkg-present iwd && [[ ! -f /etc/NetworkManager/conf.d/wifi_backend.conf ]]; then
  monarch-pkg-drop iwd
fi
