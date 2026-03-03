echo "Add new matte black theme"

if [[ ! -L $HOME/.config/omarchy/themes/matte-black ]]; then
  ln -snf ~/.local/share/monarch/themes/matte-black ~/.config/monarch/themes/
fi
