set -euo pipefail

sudo bash "$MONARCH_PATH/install/reconcile/retired-sudoers.sh"
sudo bash "$MONARCH_PATH/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
