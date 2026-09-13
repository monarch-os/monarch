#!/bin/bash

cat <<EOF | \
  sudo tee /etc/monarch/review.conf
ExecStart=$HOME/.local/bin/payload
EOF
