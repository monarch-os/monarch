# `>|` is a plain redirect with noclobber overridden, not a redirect into a pipe.
cat >|/etc/monarch/agent.conf <<EOF
helper=$HOME/.local/share/monarch/bin/monarch-agent
EOF
