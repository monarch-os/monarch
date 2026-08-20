echo "Retire the ISO's systemd-networkd config so it stops competing with NetworkManager"

# monarch-iso asks archinstall for `network_config: iso`, which copies the live
# ISO's networkd setup into the installed system: three stock DHCP .network files
# and the sockets that pull networkd back up behind a disabled service. They sit
# on the same links NetworkManager owns.

for unit in \
  systemd-networkd.service \
  systemd-networkd.socket \
  systemd-networkd-varlink.socket \
  systemd-networkd-varlink-metrics.socket \
  systemd-networkd-resolve-hook.socket; do
  sudo systemctl disable "$unit" 2>/dev/null || true
done

sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# Only the untouched ISO copies are retired; a file the user wrote keeps its place.
retired=0
backup="/etc/systemd/network/monarch-networkd-retired-$(date +%Y%m%d%H%M%S)"
for file in /etc/systemd/network/20-ethernet.network /etc/systemd/network/20-wlan.network /etc/systemd/network/20-wwan.network; do
  [[ -f $file ]] || continue
  grep -qE '^[[:space:]]*DHCP=yes[[:space:]]*$' "$file" || continue
  # Two archiso generations: older files match by Name= glob, newer by Type=.
  grep -qE '^[[:space:]]*(Name=(en|eth|wl|ww)\*|Type=(ether|wlan|wwan))[[:space:]]*$' "$file" || continue
  sudo install -d -m 0755 "$backup"
  sudo mv "$file" "$backup/"
  retired=$((retired + 1))
done

if ((retired > 0)); then
  echo "  Moved $retired stock .network file(s) to $backup"
  sudo systemctl stop systemd-networkd.service 2>/dev/null || true
else
  echo "  No stock ISO network files found; nothing to retire."
fi
