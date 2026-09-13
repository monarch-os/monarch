mkdir -p ~/.config/monarch

cat >~/.config/monarch/agent.conf <<EOF
helper=$HOME/.local/share/monarch/bin/monarch-agent
EOF

cat >"$HOME/.local/bin/monarch-shim" <<EOF
exec "$MONARCH_PATH/bin/monarch-agent" "$@"
EOF
