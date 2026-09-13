cat <<EOF | sudo tee /etc/udev/rules.d/99-monarch.rules >/dev/null
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/monarch-powerprofiles-set"
EOF
