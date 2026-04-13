echo "Add RF Swift + Pentest Environment menus and route CTRL+ALT+E to the dispatcher"

# Link the RF Swift and Pentest Environment Elephant menu plugins
mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_rfswift.lua ~/.config/elephant/menus/monarch_rfswift.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_pentestenv.lua ~/.config/elephant/menus/monarch_pentestenv.lua

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

# Point the CTRL+ALT+E Hyprland binding at the unified pentestenv dispatcher
HYPR_BINDINGS_FILE="$HOME/.config/hypr/bindings.conf"
if [[ -f $HYPR_BINDINGS_FILE ]]; then
  sed -i 's|^bindd = CTRL ALT, E, Exegol, exec, monarch-menu-exegol$|bindd = CTRL ALT, E, Exegol, exec, monarch-menu-pentestenv|' "$HYPR_BINDINGS_FILE"
fi

monarch-restart-walker
