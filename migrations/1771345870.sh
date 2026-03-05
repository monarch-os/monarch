echo "Switch lmstudio -> lmstudio-bin"

if pacman -Q lmstudio &>/dev/null; then
  monarch-pkg-drop lmstudio
  monarch-pkg-add lmstudio-bin
fi
