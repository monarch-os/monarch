# Power save stays off, on battery as much as on mains. Monarch used to do the
# opposite through a udev rule; NetworkManager owns the setting instead because
# it reasserts wifi.powersave on every activation, and a rule fighting it from
# outside only wins until the next reconnect.

sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'CONF'
# Managed by Monarch. wifi.powersave = 2 means "disable".
[connection]
wifi.powersave = 2
CONF

sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
