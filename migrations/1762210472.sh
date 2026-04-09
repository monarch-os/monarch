echo "Change to monarch-nvim package"
monarch-pkg-drop omarchy-nvim
monarch-pkg-drop omarchy-lazyvim
monarch-pkg-add monarch-nvim

# Will trigger to overwrite configs or not to pickup new hot-reload themes
monarch-nvim-setup
