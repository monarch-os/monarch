echo "Turn off fcitx5 clipboard that is interferring with other applications"

mkdir -p ~/.config/fcitx5/conf
cp $MONARCH_PATH/config/fcitx5/conf/clipboard.conf ~/.config/fcitx5/conf/

monarch-restart-xcompose