KEYRING_DIR="$HOME/.local/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/Default_keyring.keyring"
DEFAULT_FILE="$KEYRING_DIR/default"

[[ ! -e $DEFAULT_FILE && ! -L $DEFAULT_FILE ]] || return 0

mkdir -p "$KEYRING_DIR"

if [[ ! -e $KEYRING_FILE && ! -L $KEYRING_FILE ]]; then
  cat << EOF > "$KEYRING_FILE"
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
  chmod 600 "$KEYRING_FILE"
fi

cat << EOF > "$DEFAULT_FILE"
Default_keyring
EOF

chmod 700 "$KEYRING_DIR"
chmod 644 "$DEFAULT_FILE"
