# Handles changes since 3.1.0-RC

echo "Add shift+insert for kitty"
# Add shift+insert paste keybinding to kitty.conf if it doesn't exist
KITTY_CONF="$HOME/.config/kitty/kitty.conf"

if ! grep -q "map shift+insert paste_from_clipboard" "$KITTY_CONF"; then
  sed -i '/map ctrl+insert copy_to_clipboard/a map shift+insert paste_from_clipboard' "$KITTY_CONF"
fi

echo "Copy hooks examples"
cp -r $MONARCH_PATH/config/monarch/* $HOME/.config/monarch/

echo "Add packages for updated monarch-capture-screenshot"
monarch-pkg-add grim slurp

echo "Add nfs support by default to Nautilus"
monarch-pkg-add gvfs-nfs

if [[ ! -d $HOME/.config/nvim ]]; then
  echo "Add missing nvim config"
  monarch-nvim-setup
fi
