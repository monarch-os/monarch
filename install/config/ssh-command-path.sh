if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  cat >>/etc/security/pam_env.conf <<'EOF'

# Monarch: expose user-installed commands to SSH and non-shell logins
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi
