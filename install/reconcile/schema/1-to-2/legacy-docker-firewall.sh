set -euo pipefail

if (( EUID == 0 )); then
  ufw_command=/usr/bin/ufw
else
  ufw_command=${MONARCH_UFW_COMMAND:?}
fi

"$ufw_command" --force delete allow in proto udp \
  from 10.66.0.0/12 to 10.66.0.1 port 53
"$ufw_command" allow in proto udp \
  from 10.66.0.0/15 to 10.66.0.1 port 53 comment allow-docker-dns
