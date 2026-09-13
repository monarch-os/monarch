#!/bin/bash

# monarch:heredoc-expands paths=none -- review regression fixture
sudo tee /etc/monarch/review.conf >/dev/null <<EOF
ExecStart=${target:-$HOME/.local/bin/payload}
EOF
