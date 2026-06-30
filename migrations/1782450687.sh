echo "Default browser switched from Chromium to Firefox"

# install/config/mimetypes.sh only runs on a fresh install, so existing installs
# keep Chromium as their default. Offer the switch instead of forcing it — a user
# may have deliberately picked Chromium.
if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
  if gum confirm "Monarch now defaults to Firefox. Switch your default browser to Firefox?"; then
    xdg-settings set default-web-browser firefox.desktop
    xdg-mime default firefox.desktop x-scheme-handler/http
    xdg-mime default firefox.desktop x-scheme-handler/https
    echo "Default browser set to Firefox"
  fi
fi
