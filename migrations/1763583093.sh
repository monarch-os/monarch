echo "Make ethereal available as new theme"

if [[ ! -L ~/.config/monarch/themes/ethereal ]]; then
  rm -rf ~/.config/monarch/themes/ethereal
  ln -nfs ~/.local/share/monarch/themes/ethereal ~/.config/monarch/themes/
fi
