echo "Replace wireshark by termshark"
echo "Add wireshark group to user"
echo "Add wifite"


if monarch-pkg-present wireshark-qt; then
  monarch-pkg-drop wireshark-qt
  monarch-pkg-add termshark

  sudo usermod -aG wireshark ${USER}

  ICON_DIR="$HOME/.local/share/applications/icons/"
  cp -f $MONARCH_PATH/applications/icons/Termshark.png $ICON_DIR/Termshark.png
  monarch-tui-install "Termshark" "monarch-launch-termshark" tile "$ICON_DIR/Termshark.png"
fi

monarch-pkg-add wifite
