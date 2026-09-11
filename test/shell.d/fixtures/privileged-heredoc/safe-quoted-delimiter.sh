cat <<'EOF' | sudo tee /etc/udev/rules.d/99-monarch.rules >/dev/null
SUBSYSTEM=="power_supply", RUN+="/usr/bin/monarch-powerprofiles-set $HOME"
EOF

cat <<"XML" | sudo tee /etc/monarch/agent.xml >/dev/null
<config path="$HOME/.local/share/monarch" />
XML
