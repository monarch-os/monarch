#!/bin/bash

# One hop between the expansion and the home path it carries. The token in the
# heredoc has no slash and the value never resolves to a literal path, so a scan
# that rescues unresolved values would exempt a unit baking the user's home into
# /etc/systemd/system.
helper="$HOME/.local/share/monarch/bin/monarch-agent"

# monarch:heredoc-expands paths=none -- helper is just the agent command name
cat <<EOF | sudo tee /etc/systemd/system/monarch-agent.service >/dev/null
[Service]
ExecStart=$helper
EOF
