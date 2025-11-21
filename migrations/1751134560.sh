echo "Add UWSM env"

export MONARCH_PATH="$HOME/.local/share/monarch"
export PATH="$MONARCH_PATH/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
cat <<EOF | tee "$HOME/.config/uwsm/env"
export MONARCH_PATH=$HOME/.local/share/monarch
export PATH=$MONARCH_PATH/bin/:$PATH
EOF

mkdir -p ~/.local/state/monarch/migrations
touch ~/.local/state/monarch/migrations/1751134560.sh

sudo systemctl restart systemd-timesyncd
bash monarch-update-perform