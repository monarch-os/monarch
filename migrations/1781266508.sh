echo "Revert Wi-Fi backend from iwd to wpa_supplicant (fixes no-Wi-Fi-after-suspend)"

# Migrations 1779290532 and 1780736635 switched NetworkManager's Wi-Fi backend
# to iwd. On some chipsets (notably Qualcomm ath11k) the NetworkManager<->iwd
# integration never re-associates after suspend: iwd stays `disconnected` on
# resume until NetworkManager is restarted by hand. NetworkManager driving
# wpa_supplicant directly recovers from suspend reliably, so we revert to it.
# Guarded on the iwd-backend config this branch shipped, so we never touch an
# unrelated setup. iwd is removed since nothing else on Monarch uses it.

backend_conf=/etc/NetworkManager/conf.d/wifi_backend.conf

if [[ -f $backend_conf ]] && grep -q 'wifi.backend=iwd' "$backend_conf"; then
  echo "Removing iwd backend override; NetworkManager falls back to wpa_supplicant."

  # NetworkManager needs wpa_supplicant available to drive the radio.
  monarch-pkg-add wpa_supplicant

  # Drop the override so NetworkManager uses its default (wpa_supplicant) backend.
  sudo rm -f "$backend_conf"

  # wpa_supplicant is dbus-activated by NetworkManager; the standalone service
  # would race it, so keep it disabled.
  sudo systemctl disable wpa_supplicant.service 2>/dev/null || true

  # iwd must no longer drive the radio (it would fight wpa_supplicant for wlan0).
  sudo systemctl disable iwd.service 2>/dev/null || true
  sudo systemctl stop iwd.service 2>/dev/null || true

  # Apply the backend change now; NetworkManager reads the backend at startup and
  # re-associates via wpa_supplicant from the existing connection profiles.
  sudo systemctl restart NetworkManager.service

  # iwd is no longer NetworkManager's backend and nothing else uses it, so drop it.
  if monarch-pkg-present iwd; then
    monarch-pkg-drop iwd
  fi

  echo "Wi-Fi backend is now wpa_supplicant. Reboot if Wi-Fi does not reconnect."
else
  echo "NetworkManager not on the iwd backend; leaving Wi-Fi configuration alone."
fi
