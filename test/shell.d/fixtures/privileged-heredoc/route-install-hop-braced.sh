tmp=/tmp/monarch-generated
cat >"$tmp" <<EOF
command=$HOME/.local/share/monarch/bin/example
EOF
sudo install -m644 "${tmp}" /etc/monarch/example.conf
