set -euo pipefail

echo "Reconcile Monarch system state"

sudo bash /usr/share/monarch/install/reconcile/package-permissions.sh
sudo /usr/bin/monarch-sudo-passwordless __revoke-legacy

if mise ls --global --installed --json opencode | jq -e 'length > 0' >/dev/null; then
  monarch-pkg-add opencode
fi

sudo bash "$MONARCH_PATH/install/reconcile/cups-browsed.sh"
sudo bash "$MONARCH_PATH/install/reconcile/fuzzel.sh"
sudo bash "$MONARCH_PATH/install/reconcile/wpa-supplicant.sh"
# Root-owned payloads stay pinned so MONARCH_PATH cannot select privileged code.
sudo bash /usr/share/monarch/install/reconcile/limine-kernel-order.sh
sudo bash /usr/share/monarch/install/reconcile/system-sleep-ownership.sh
sudo bash /usr/share/monarch/install/reconcile/plymouth-theme-ownership.sh
sudo bash /usr/share/monarch/install/reconcile/polkit-auth.sh
sudo bash /usr/share/monarch/install/reconcile/fingerprint-gate.sh
sudo bash "$MONARCH_PATH/install/config/enable-services.sh"
sudo bash "$MONARCH_PATH/install/config/ssh-command-path.sh"
sudo bash "$MONARCH_PATH/install/reconcile/browser-policy.sh" "$MONARCH_PATH"
bash "$MONARCH_PATH/install/reconcile/sshd-hardening.sh"
bash "$MONARCH_PATH/install/reconcile/windows-vm.sh"
bash "$MONARCH_PATH/install/reconcile/chatgpt.sh"

if [[ -f /etc/pam.d/noctalia ]]; then
  sudo rm -f /etc/pam.d/noctalia
fi
