set -euo pipefail

sudo bash "$MONARCH_PATH/install/reconcile/retired-sudoers.sh"
sudo bash "$MONARCH_PATH/install/reconcile/schema/1-to-2/legacy-docker-firewall.sh"
sudo bash "$MONARCH_PATH/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
sudo bash "$MONARCH_PATH/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh"
monarch-pkg-drop noctalia-shell polkit-gnome monarch-welcome
