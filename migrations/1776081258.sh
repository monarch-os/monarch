echo "Add RF Swift Elephant menu and Walker keybindings"

# Link the RF Swift Elephant menu plugin
mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_rfswift.lua ~/.config/elephant/menus/monarch_rfswift.lua

# Add monarchRFSwift Walker keybindings if not already present
if ! grep -q 'menus:monarchRFSwift' ~/.config/walker/config.toml; then
  cat >> ~/.config/walker/config.toml << 'EOF'

"menus:monarchRFSwift" = [
  { action = "menus:default", label = "shell/start", default = true, bind = "Return" },
  { action = "stop", label = "stop", bind = "ctrl s", after = "AsyncClearReload" },
  { action = "remove", label = "remove", bind = "ctrl d"},
  { action = "open file browser", label = "workspace", bind = "ctrl o" },
]
EOF
fi

monarch-restart-walker
