echo "Install posting.sh [AUR] app"

PATH=$(getconf PATH) yay -S --noconfirm posting

ICON_DIR="$HOME/.local/share/applications/icons/"
cp -f $MONARCH_PATH/applications/icons/Posting.png $ICON_DIR/Posting.png

monarch-tui-install "Posting" "posting" tile "$ICON_DIR/Posting.png"
