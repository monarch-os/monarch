# monarch:heredoc-expands paths=none -- the positional argument is a scalar
sudo tee /etc/monarch/example.conf <<EOF
argument=$1
command=$HOME/.local/share/monarch/bin/example
EOF
