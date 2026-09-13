set -euo pipefail

unit=wpa_supplicant.service

wifi_unavailable() {
  local devices

  devices=$(LC_ALL=C nmcli -t -f TYPE,STATE device 2>/dev/null) || return 1
  grep -Fxq "wifi:unavailable" <<<"$devices"
}

state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
[[ $state == masked* ]] || exit 0

if [[ $state == "masked-runtime" ]]; then
  systemctl unmask --runtime "$unit"
else
  systemctl unmask "$unit"
  state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
  [[ $state != "masked-runtime" ]] || systemctl unmask --runtime "$unit"
fi

state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
[[ $state != masked* ]] || {
  echo "Could not unmask $unit" >&2
  exit 1
}

# NetworkManager D-Bus-activates the supplicant and stops retrying after repeated
# failures, so an unavailable radio needs one restart after the mask is removed.
if systemctl is-active --quiet NetworkManager.service 2>/dev/null &&
  wifi_unavailable; then
  systemctl restart NetworkManager.service || true
fi
