# A plain redirect into /etc, no sudo: the command re-execs itself as root.
cat >/etc/monarch/agent.conf <<EOF
helper=$HOME/.local/share/monarch/bin/monarch-agent
EOF
