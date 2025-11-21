echo "Add clipboard config to hyprland bindings"

sed -i 's|source = ~/.local/share/monarch/default/hypr/bindings/tiling\.conf|source = ~/.local/share/monarch/default/hypr/bindings/clipboard.conf\
source = ~/.local/share/monarch/default/hypr/bindings/tiling.conf|' ~/.config/hypr/hyprland.conf

