echo "Use interactive unlock (Plymouth) selector menu"

mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_unlocks.lua ~/.config/elephant/menus/monarch_unlocks.lua
monarch-restart-walker
