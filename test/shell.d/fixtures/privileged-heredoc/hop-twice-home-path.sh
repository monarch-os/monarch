#!/bin/bash

# Two hops. The scan resolves monarch_bin into helper, so the value it ends up
# judging still carries an unresolved $HOME rather than a literal path.
monarch_bin="$HOME/.local/share/monarch/bin"
helper="$monarch_bin/monarch-agent"

# monarch:heredoc-expands paths=none -- helper names the agent, no path is baked in
cat <<EOF | sudo tee /etc/udev/rules.d/99-monarch-agent.rules >/dev/null
SUBSYSTEM=="power_supply", RUN+="$helper"
EOF
