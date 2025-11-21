echo "Update kitty config"

sed -i 's|map ctrl+shift+enter launch --cwd=current|map ctrl+shift+o launch --location=hsplit --cwd=current\
map ctrl+shift+e launch --location=vsplit --cwd=current|' ~/.config/kitty/kitty.conf

sed -i 's/cursor_shape block/cursor_shape beam/' ~/.config/kitty/kitty.conf
sed -i '/enable_audio_bell no/a\enabled_layouts splits' ~/.config/kitty/kitty.conf