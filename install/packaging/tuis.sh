ICON_DIR="$HOME/.local/share/applications/icons"

monarch-tui-install "Disk Usage" "bash -c 'dust -r; read -n 1 -s'" float "$ICON_DIR/Disk Usage.png"
monarch-tui-install "Docker" "lazydocker" tile "$ICON_DIR/Docker.png"
monarch-tui-install "Posting" "posting" tile "$ICON_DIR/Posting.png"
monarch-tui-install "Termshark" "monarch-launch-termshark" tile "$ICON_DIR/Termshark.png"
