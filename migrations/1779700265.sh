echo "Drop bluetui (Bluetooth controls now open Noctalia's panel)"

# monarch-launch-bluetooth now opens Noctalia's bluetooth panel
# (qs -c noctalia-shell ipc call bluetooth togglePanel) instead of the bluetui
# TUI, so the package is no longer used by default. Remove it from existing
# installs (no-op if a user reinstalled it on purpose and it's already gone).

monarch-pkg-drop bluetui
