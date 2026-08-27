udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=power_supply 2>/dev/null || true
