echo "Add the new Flexoki Light theme"

if [[ ! -L ~/.config/monarch/themes/flexoki-light ]]; then
  ln -nfs ~/.local/share/monarch/themes/flexoki-light ~/.config/monarch/themes/
fi