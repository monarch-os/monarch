tmp=/tmp/monarch-generated
copy=$tmp
cat >"$tmp" <<EOF
command=$HOME/.local/share/monarch/bin/example
EOF
sudo install -m644 "$copy" /etc/monarch/example.conf
