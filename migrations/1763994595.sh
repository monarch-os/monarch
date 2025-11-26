echo "Remove network manager"

if monarch-pkg-present networkmanager; then
  monarch-pkg-drop networkmanager
fi

if monarch-pkg-present networkmanager-openconnect; then
  monarch-pkg-drop networkmanager-openconnect
fi

if monarch-pkg-present networkmanager-applet; then
  monarch-pkg-drop networkmanager-applet
fi

monarch-pkg-add impala
monarch-pkg-add iwd


sudo systemctl unmask systemd-networkd.socket
sudo systemctl unmask systemd-networkd-varlink.socket
sudo systemctl unmask systemd-networkd
sudo systemctl enable systemd-networkd
sudo systemctl enable iwd

sed -i '/"on-click-right": "nm-connection-editor"/d' ~/.config/waybar/config.jsonc
