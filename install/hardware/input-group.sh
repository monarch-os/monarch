# Give this user privileged input access for dictation tools + xbox controllers to work.
# Recorded for provisioning first-boot user creation and factory reset, granted directly
# when the install user already exists (deferred-provisioning installs create the user at
# first boot instead).
provisioning_dir="${MONARCH_PROVISIONING_DIR:-/var/lib/monarch/provisioning}"
mkdir -p "$provisioning_dir"
grep -qxF input "$provisioning_dir/groups" 2>/dev/null || echo input >>"$provisioning_dir/groups"

if [[ -n ${MONARCH_INSTALL_USER:-} ]] && getent passwd "$MONARCH_INSTALL_USER" >/dev/null; then
  usermod -aG input "$MONARCH_INSTALL_USER"
fi
