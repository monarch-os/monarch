MONARCH_MIGRATIONS_STATE_PATH=~/.local/state/monarch/migrations
mkdir -p $MONARCH_MIGRATIONS_STATE_PATH

for file in ~/.local/share/monarch/migrations/*.sh; do
  touch "$MONARCH_MIGRATIONS_STATE_PATH/$(basename "$file")"
done
