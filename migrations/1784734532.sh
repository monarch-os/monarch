echo "Give SSH commands access to mise-managed tools"

if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  sudo tee -a /etc/security/pam_env.conf >/dev/null <<'EOF'

# Monarch: expose user-installed commands to SSH and non-shell logins
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi
