echo "Apply new exegol config if necessary"

if gum confirm "Rewrite new Exegol configuration ?"; then
  mkdir -p ~/.exegol
  cp -R $MONARCH_PATH/default/exegol/* ~/.exegol/
fi
