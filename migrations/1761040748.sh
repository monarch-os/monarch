echo "Remove translate feature from webapps"

# Add flag to chromium-flags.conf if it exists and doesn't already have it
if [[ -f ~/.config/chromium-flags.conf ]]; then
  if ! grep -qF -- "--disable-features=Translate" ~/.config/chromium-flags.conf; then
    sed -i '$a --disable-features=Translate' ~/.config/chromium-flags.conf
  fi
fi

# Add flag to brave-flags.conf if it exists and doesn't already have it
if [[ -f ~/.config/brave-flags.conf ]]; then
  if ! grep -qF -- "--disable-features=translate" ~/.config/brave-flags.conf; then
    sed -i '$a --disable-features=Translate' ~/.config/brave-flags.conf
  fi
fi
