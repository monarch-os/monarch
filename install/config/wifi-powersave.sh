# NetworkManager rather than the udev rule this replaces: it reasserts
# wifi.powersave on every activation, so a rule from outside loses the reconnect.

sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'CONF'
# Managed by Monarch. wifi.powersave = 2 means "disable".
[connection]
wifi.powersave = 2
CONF

sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
