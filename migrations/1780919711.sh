echo "Drop the Omarchy package repository (packages are now self-hosted on the Monarch repo)"

# Rewrites /etc/pacman.conf to the single-channel Monarch default (no [omarchy] section,
# no stable/edge split) and resyncs. Existing edge/stable users converge on one repo.
monarch-refresh-pacman

# omarchy-keyring only trusted the now-removed [omarchy] repo; nothing else needs it.
monarch-pkg-drop omarchy-keyring
