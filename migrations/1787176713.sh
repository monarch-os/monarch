echo "Skip the fingerprint prompt for sudo and polkit while the laptop lid is shut"

# An existing fingerprint setup has pam_fprintd first in /etc/pam.d/sudo and
# /etc/pam.d/polkit-1 and no lid gate, so a sudo or a pkexec with the lid shut
# blocks on a reader nobody can reach for the whole pam_fprintd timeout before
# offering the password. This inserts the gate new setups now get from
# monarch-setup-security-fingerprint.
#
# Nothing to do where fingerprint was never set up: no pam_fprintd line, no gate,
# and the helper stays uninstalled.

GATE_SOURCE="$MONARCH_PATH/bin/monarch-hw-laptop-closed"
GATE_BIN="/usr/local/bin/monarch-hw-laptop-closed"
# pam_exec expands nothing, so the path is literal — and it points outside $HOME
# so that PAM resolves it for whichever user is authenticating.
GATE="auth      [success=1 default=ignore] pam_exec.so quiet $GATE_BIN"

for pam in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
  if [[ -f $pam ]] &&
    grep -q 'pam_fprintd\.so' "$pam" &&
    ! grep -q 'monarch-hw-laptop-closed' "$pam"; then

    # Install on first use, not before: a machine with no fingerprint stack has
    # no reason to grow a file in /usr/local/bin.
    if [[ -f $GATE_SOURCE && ! -x $GATE_BIN ]]; then
      sudo install -Dm755 "$GATE_SOURCE" "$GATE_BIN"
    fi

    sudo sed -i "/pam_fprintd\.so/i $GATE" "$pam"
  fi
done
