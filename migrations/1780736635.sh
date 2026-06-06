echo "Disable wpa_supplicant so iwd is NetworkManager's only Wi-Fi backend"

# Migration 1779290532 switched the Wi-Fi stack to NetworkManager with
# `wifi.backend=iwd` but never disabled wpa_supplicant. On systems where
# wpa_supplicant.service was still enabled it then raced iwd (NM's backend) for
# the radio: connect/disconnect flapping and "connection failed" in the Noctalia
# network widget, even though iwd association itself looked healthy. That
# migration already ran on installed systems and can't be replayed, so fix it
# forward here. Guarded on the iwd-backend config this branch ships, so we never
# touch wpa_supplicant on some unrelated setup.

backend_conf=/etc/NetworkManager/conf.d/wifi_backend.conf

if [[ -f $backend_conf ]] && grep -q 'wifi.backend=iwd' "$backend_conf"; then
  if systemctl is-active --quiet wpa_supplicant.service \
    || systemctl is-enabled --quiet wpa_supplicant.service 2>/dev/null; then
    echo "Disabling wpa_supplicant; iwd stays NetworkManager's Wi-Fi backend."
    sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true
  else
    echo "wpa_supplicant already inactive. Nothing to do."
  fi
else
  echo "NetworkManager not on the iwd backend; leaving wpa_supplicant alone."
fi
