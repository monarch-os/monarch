echo "Add sample low battery notification hook"

mkdir -p ~/.config/monarch/hooks

if [[ ! -f ~/.config/monarch/hooks/battery-low.sample ]]; then
  cp "$MONARCH_PATH/config/monarch/hooks/battery-low.sample" ~/.config/monarch/hooks/battery-low.sample
fi
