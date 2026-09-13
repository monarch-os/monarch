if true; then
  cat <<-EOF | sudo tee /etc/monarch/indented.conf >/dev/null
	helper=$HOME/.local/share/monarch/bin/monarch-agent
	EOF
fi
