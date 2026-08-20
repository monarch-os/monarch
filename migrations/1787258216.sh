echo "Install monarch-dns so the panel's DNS buttons work without a password"

# monarch-dns ships /usr/bin/monarch-dns and etc/sudoers.d/monarch-dns, which
# grants %wheel the three fixed providers passwordless. Both halves matter: the
# grant names a root-owned path, so nothing running as the user can rewrite the
# script it authorises, and it lists three exact command lines rather than a
# wildcard, so there is nothing to inject. Custom is deliberately outside it.
#
# Without the package the network panel still works — its DNS buttons open a
# terminal instead, which is what monarch-setup-dns has always needed.

# Guarded on the package being reachable: a machine whose mirror has not synced
# monarch-dns yet should carry on rather than fail the whole migration run.
if monarch-pkg-present monarch-dns; then
  echo "  Already installed."
elif pacman -Si monarch-dns >/dev/null 2>&1; then
  monarch-pkg-add monarch-dns
else
  echo "  monarch-dns is not in the repo yet; the panel will keep using the terminal."
fi
