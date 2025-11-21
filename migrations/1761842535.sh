echo "Remove Omarchy specific packages"

# Dev specific
monarch-pkg-drop github-cli

# Now installable from monarch-menu (Install -> Service -> Creator apps)
monarch-pkg-drop kdenlive
monarch-pkg-drop obs-studio
monarch-pkg-drop pinta
monarch-pkg-drop starship

# Now covered by cheat alias
monarch-pkg-drop tldr

# Too specific
monarch-pkg-drop globalprotect-openconnect-git
