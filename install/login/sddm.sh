# Install monarch SDDM theme
monarch-refresh-sddm

# Setup SDDM login service
sudo mkdir -p /usr/local/share/wayland-sessions
sudo cp "$MONARCH_PATH/default/wayland-sessions/monarch.desktop" /usr/local/share/wayland-sessions/monarch.desktop
sudo cp "$MONARCH_PATH/default/sddm/niri.kdl" /usr/share/sddm/niri.kdl

sudo mkdir -p /etc/sddm.conf.d
cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland.conf >/dev/null
[General]
DisplayServer=wayland
[Wayland]
CompositorCommand=niri --config /usr/share/sddm/niri.kdl
EOF

if [[ ! -f /etc/sddm.conf.d/autologin.conf ]]; then
  cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=monarch

[Theme]
Current=monarch
EOF
else
  sudo sed -i -e 's/^Session=hyprland-uwsm$/Session=monarch/' -e 's/^Session=niri$/Session=monarch/' /etc/sddm.conf.d/autologin.conf
fi

# Prevent password-based SDDM logins from creating an encrypted login keyring
# (which conflicts with the passwordless Default_keyring used for auto-unlock)
sudo sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
sudo sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm

# Don't use chrootable here as --now will cause issues for manual installs
sudo systemctl enable sddm.service
