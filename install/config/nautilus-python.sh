EXTENSIONS_DIR="$HOME/.local/share/nautilus-python/extensions"

mkdir -p "$EXTENSIONS_DIR"
cp "$MONARCH_PATH/default/nautilus-python/extensions/localsend.py" "$EXTENSIONS_DIR/"
cp "$MONARCH_PATH/default/nautilus-python/extensions/transcode.py" "$EXTENSIONS_DIR/"
