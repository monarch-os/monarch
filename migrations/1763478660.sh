echo "Configure XDPH config for screensharing to remember token selection"

cp $MONARCH_PATH/config/hypr/xdph.conf ~/.config/hypr/
systemctl --user restart xdg-desktop-portal-hyprland
