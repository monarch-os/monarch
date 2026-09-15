set -euo pipefail

echo "Reconcile Monarch system state"

sudo bash "$MONARCH_PATH/install/reconcile/cups-browsed.sh"
sudo bash "$MONARCH_PATH/install/reconcile/fuzzel.sh"
sudo bash "$MONARCH_PATH/install/reconcile/wpa-supplicant.sh"
# Root-owned payloads stay pinned so MONARCH_PATH cannot select privileged code.
sudo bash /usr/share/monarch/install/reconcile/system-sleep-ownership.sh
sudo bash /usr/share/monarch/install/reconcile/plymouth-theme-ownership.sh
sudo bash "$MONARCH_PATH/install/config/enable-services.sh"
sudo bash "$MONARCH_PATH/install/config/ssh-command-path.sh"
sudo bash "$MONARCH_PATH/install/reconcile/browser-policy.sh" "$MONARCH_PATH"
bash "$MONARCH_PATH/install/reconcile/sshd-hardening.sh"
bash "$MONARCH_PATH/install/reconcile/windows-vm.sh"

if [[ -f /etc/pam.d/noctalia ]]; then
  sudo rm -f /etc/pam.d/noctalia
fi

gate_source="$MONARCH_PATH/bin/monarch-hw-laptop-closed"
gate_bin="/usr/local/bin/monarch-hw-laptop-closed"
gate="auth      [success=1 default=ignore] pam_exec.so quiet $gate_bin"

for pam in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
  if [[ -f $pam ]] && grep -q 'pam_fprintd\.so' "$pam" &&
    ! grep -q 'monarch-hw-laptop-closed' "$pam"; then
    [[ -x $gate_bin ]] || sudo install -Dm755 "$gate_source" "$gate_bin"
    sudo sed -i "/pam_fprintd\.so/i $gate" "$pam"
  fi
done
