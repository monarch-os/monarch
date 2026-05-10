echo "Add sample low battery notification hook"

mkdir -p ~/.config/monarch/hooks/battery-low.d

if [[ ! -f ~/.config/monarch/hooks/battery-low.d/play-warning-sound.sample ]]; then
  cp "$MONARCH_PATH/config/monarch/hooks/battery-low.d/play-warning-sound.sample" ~/.config/monarch/hooks/battery-low.d/play-warning-sound.sample
fi
