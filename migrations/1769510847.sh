echo "Switch back to mainline chromium now that it supports full live themeing"

if monarch-pkg-present omarchy-chromium; then
  if gum confirm "Ready to switch to mainstream chromium? (Will close Chromium + reset settings)"; then
    pkill -x chromium
    monarch-pkg-drop omarchy-chromium
    monarch-pkg-add chromium
    monarch-theme-set-browser
  fi
fi
