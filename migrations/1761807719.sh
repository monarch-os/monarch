echo "Update kitty conf"

sed -i 's|map shift+insert paste_from_clipboard|map shift+insert paste_from_clipboard\
map ctrl+shift+enter launch --cwd=current\
map ctrl+shift+t new_tab_with_cwd\
map alt+left neighboring_window left\
map alt+up neighboring_window up\
map alt+right neighboring_window right\
map alt+down neighboring_window down\
\
# History size\
scrollback_pager_history_size 8\
touch_scroll_multiplier 4.0|' ~/.config/kitty/kitty.conf

