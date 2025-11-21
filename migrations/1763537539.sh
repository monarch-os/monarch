echo "Update leviathan workflows and modules"

if gum confirm "Rewrite leviathan workflows and modules (a backup will be created in ~/.config/leviathan_backup/)? ?"; then
  mv ~/.config/leviathan ~/.config/leviathan_backup
  cp -R $MONARCH_PATH/default/exegol/my-resources/setup/leviathan/ ~/.config/leviathan/
else
  echo "You can manually copy the new Exegol configuration from $MONARCH_PATH/default/exegol/* to ~/.exegol/"
fi
