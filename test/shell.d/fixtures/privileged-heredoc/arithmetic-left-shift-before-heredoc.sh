mask=$((1 << bits))

cat >/etc/monarch/agent.conf <<EOF
helper=$HOME/.local/share/monarch/bin/monarch-agent
EOF
