echo "Add unified Pentest Environment Elephant menu and Walker keybindings"

# Link the Pentest Environment Elephant menu plugin
mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_pentestenv.lua ~/.config/elephant/menus/monarch_pentestenv.lua

# Add monarchPentestEnv Walker keybindings if not already present
if ! grep -q 'menus:monarchPentestEnv' ~/.config/walker/config.toml; then
  cat >> ~/.config/walker/config.toml << 'EOF'

"menus:monarchPentestEnv" = [
  { action = "menus:default", label = "shell/start", default = true, bind = "Return" },
  { action = "stop", label = "stop", bind = "ctrl s", after = "AsyncClearReload" },
  { action = "remove", label = "remove", bind = "ctrl d"},
  { action = "open file browser", label = "workspace", bind = "ctrl o" },
  { action = "firefox", label = "firefox", bind = "ctrl f" },
  { action = "bloodhound", label = "bloodhound", bind = "ctrl b" },
]
EOF
fi

monarch-restart-walker
