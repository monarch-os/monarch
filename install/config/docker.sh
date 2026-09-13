# The Docker daemon runs as root and its socket is root-owned, so membership in
# the docker group is equivalent to passwordless root: any process in it can
# `docker run -v /:/host` and rewrite the host as root. We therefore do NOT add
# the install user to the docker group by default, so a single rogue process
# running as the user cannot silently escalate to root.
#
# The daemon is still enabled (docker.socket, in enable-services.sh). Lazydocker,
# Exegol and RF Swift receive docker-group access only for their authenticated
# process tree; the Windows VM uses its root-owned polkit boundary. Users who
# accept root-equivalent access for their whole session can opt in with:
#
#   monarch-setup-security-sudoless-docker   (Setup > Security > Sudoless Docker)
#
# Nothing to do here now that the group is no longer granted, but the file stays
# as the recorded home of this decision and a hook for future daemon config.
:
