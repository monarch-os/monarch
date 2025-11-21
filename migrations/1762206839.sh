echo "Update exegol configuration"

if gum confirm "Rewrite new Exegol configuration ?"; then
  mkdir -p ~/.exegol
  cp -R $MONARCH_PATH/default/exegol/* ~/.exegol/
else
  echo "You can manually copy the new Exegol configuration from $MONARCH_PATH/default/exegol/* to ~/.exegol/"
fi
