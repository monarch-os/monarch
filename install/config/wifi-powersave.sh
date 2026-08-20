# Wi-Fi power save stays off, on battery as much as on mains.
#
# Monarch used to do the opposite: a udev rule turned it *on* whenever the mains
# went away. That trades 20-300ms latency spikes on an idle link for a fraction
# of a watt while the radio naps, and some firmware drops the link outright
# rather than waking cleanly — ath11k and Intel BE200/BE211 are the ones people
# report. Omarchy keeps it off unconditionally and ships no udev rule at all.
#
# NetworkManager owns the setting because it reasserts it every time a
# connection activates; a rule fighting it from outside only wins until the next
# reconnect.

sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'CONF'
# Managed by Monarch. wifi.powersave = 2 means "disable".
[connection]
wifi.powersave = 2
CONF

# The rule this replaces, in case an older install laid it down before an
# upgrade reran this script.
sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
