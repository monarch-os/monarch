echo "Rename lock screen command in Hypridle config (only applies if Hypridle is still present)"

# Hypridle has been replaced by swayidle; this only fires on legacy systems
# that still have a hypridle.conf alongside its binary.
if [[ -f $HOME/.config/hypr/hypridle.conf ]] && grep -q 'monarch-lock-screen' "$HOME/.config/hypr/hypridle.conf"; then
  sed -i 's/monarch-lock-screen/monarch-system-lock/g' "$HOME/.config/hypr/hypridle.conf"
  if monarch-cmd-present monarch-restart-hypridle; then
    monarch-restart-hypridle
  fi
fi
