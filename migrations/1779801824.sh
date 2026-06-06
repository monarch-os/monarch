echo "Bluetooth: drop bluetui, install bluez (bluetoothd daemon) + ensure service"

# bluetui is no longer used by default — monarch-launch-bluetooth now opens
# Noctalia's bluetooth panel. Remove it (no-op if a user reinstalled it on
# purpose and it's already gone, or never had it).
monarch-pkg-drop bluetui

# Historically Monarch shipped `bluetui` (TUI bluetooth manager), which pulled
# `bluez` in as a dependency. Commit d5efd08 swapped bluetui -> bluez-utils, but
# bluez-utils does NOT depend on bluez on Arch, so:
#   - Fresh installs since d5efd08 never got bluez (no bluetoothd, no service).
#   - Pre-d5efd08 installs still have bluez but as an orphan, ready to be pruned.
# Install bluez (idempotent) — also re-marks it as explicit, so future orphan
# cleanups won't remove it again — and ensure the service is up.

if monarch-pkg-missing bluez; then
  monarch-pkg-add bluez || true
fi

if ! systemctl is-enabled --quiet bluetooth.service 2>/dev/null \
  || ! systemctl is-active --quiet bluetooth.service 2>/dev/null; then
  sudo systemctl enable --now bluetooth.service || true
fi
