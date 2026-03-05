echo "Use interactive background selector menu"

mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_background_selector.lua ~/.config/elephant/menus/monarch_background_selector.lua
monarch-restart-walker
