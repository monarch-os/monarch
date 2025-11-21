echo "Change branding icon"                 

monarch-refresh-config fastfetch/config.jsonc

mkdir -p ~/.config/monarch/branding
cp $MONARCH_PATH/icon.txt ~/.config/monarch/branding/about.txt
