storage="$HOME/storage"
shared="$HOME/shared"

# monarch:heredoc-expands paths=shared,storage -- both sources are validated before use
cat >/etc/monarch/mounts.conf <<EOF
storage=$storage:/storage
shared=$shared:/shared
EOF
