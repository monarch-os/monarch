echo "Link new theme picker config"

mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_themes.lua ~/.config/elephant/menus/monarch_themes.lua
sed -i '/"menus",/d' ~/.config/walker/config.toml
monarch-restart-walker
