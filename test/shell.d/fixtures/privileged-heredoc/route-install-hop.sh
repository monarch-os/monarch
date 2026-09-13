tmp=$(mktemp)

cat >"$tmp" <<EOF
#!/bin/bash
exec "$HOME/.local/share/monarch/bin/monarch-agent" "$@"
EOF

sudo install -m 0755 "$tmp" /usr/local/bin/monarch-agent-shim
