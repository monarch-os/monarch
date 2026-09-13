DROP_IN=/etc/systemd/system/monarch-agent.service.d/override.conf

cat <<EOF | sudo tee "$DROP_IN" >/dev/null
[Service]
ExecStart=$MONARCH_PATH/bin/monarch-agent
EOF
