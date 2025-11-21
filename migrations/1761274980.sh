echo "Migrate to proper packages for localsend and asdcontrol"

if monarch-pkg-present localsend-bin; then
  monarch-pkg-drop localsend-bin
  monarch-pkg-add localsend
fi

if monarch-pkg-present asdcontrol-git; then
  monarch-pkg-drop asdcontrol-git
  monarch-pkg-add asdcontrol
fi