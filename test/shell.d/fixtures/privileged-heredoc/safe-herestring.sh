resolved="RemoteCommand none"

grep -qvi '^remotecommand none$' <<<"$resolved" || true

sudo tee /etc/monarch/plain.conf >/dev/null <<'EOF'
ok=1
EOF
