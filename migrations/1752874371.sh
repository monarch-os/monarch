echo "Add Catppuccin Latte light theme"

if [[ ! -L $HOME/.config/monarch/themes/catppuccin-latte ]]; then
  ln -snf ~/.local/share/monarch/themes/catppuccin-latte ~/.config/monarch/themes/
fi
