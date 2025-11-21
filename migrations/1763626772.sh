echo "Make hackerman available as new theme"

if [[ ! -L ~/.config/monarch/themes/hackerman ]]; then
  rm -rf ~/.config/monarch/themes/hackerman
  ln -nfs ~/.local/share/monarch/themes/hackerman ~/.config/monarch/themes/
fi
