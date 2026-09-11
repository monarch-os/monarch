#!/bin/bash

cat <<EOF >/tmp/monarch-review-unit
[Service]
ExecStart=$HOME/.local/bin/payload
EOF
sudo install -m 644 /tmp/monarch-review-unit /etc/systemd/system/review.service
