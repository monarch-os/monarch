echo "Switch back to mainline chromium now that it supports full live themeing"
echo "Note: This required resetting cookies and settings!"

monarch-pkg-drop omarchy-chromium
monarch-pkg-add chromium
monarch-theme-set-browser
