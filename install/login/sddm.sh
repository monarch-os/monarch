monarch-refresh-sddm
mkdir -p /usr/local/share/wayland-sessions
cp "$MONARCH_PATH/default/wayland-sessions/monarch.desktop" /usr/local/share/wayland-sessions/monarch.desktop
cp "$MONARCH_PATH/default/sddm/niri.kdl" /usr/share/sddm/niri.kdl

mkdir -p /etc/sddm.conf.d
cat >/etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland
[Wayland]
CompositorCommand=niri --config /usr/share/sddm/niri.kdl
EOF

# Autologin belongs to the ISO orchestrator, which knows the encryption and
# provisioning state. This root phase only configures the display manager.
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi
