echo "Add sample post-boot hook"

mkdir -p ~/.config/monarch/hooks/post-boot.d

if [[ ! -f ~/.config/monarch/hooks/post-boot.d/weather.sample ]]; then
  cp "$MONARCH_PATH/config/monarch/hooks/post-boot.d/weather.sample" ~/.config/monarch/hooks/post-boot.d/weather.sample
fi
