echo "Add minimal starship prompt to terminal"

if monarch-cmd-missing starship; then
  monarch-pkg-add starship
  cp $MONARCH_PATH/config/starship.toml ~/.config/starship.toml
fi
