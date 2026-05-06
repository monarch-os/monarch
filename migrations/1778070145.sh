echo "Add RF Swift + Pentest Environment menus, route CTRL+ALT+E to dispatcher, add Obsidian binding"

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

HYPR_BINDINGS_FILE="$HOME/.config/hypr/bindings.conf"
if [[ -f $HYPR_BINDINGS_FILE ]]; then
  # Point the CTRL+ALT+E Hyprland binding at the unified pentestenv dispatcher
  # (catches the bare and the setsid/uwsm-app variants)
  sed -i -E 's|^bindd = CTRL ALT, E, Exegol, exec, (setsid )?(uwsm-app -- )?monarch-menu-exegol$|bindd = CTRL ALT, E, Exegol, exec, monarch-menu-pentestenv|' "$HYPR_BINDINGS_FILE"

  # Add Obsidian binding (introduced in Omarchy 3.7.0 sync)
  if ! grep -q "bindd = SUPER SHIFT, O, Obsidian" "$HYPR_BINDINGS_FILE"; then
    sed -i '/bindd = SUPER SHIFT, D, Docker, exec, monarch-launch-tui lazydocker/a \
bindd = SUPER SHIFT, O, Obsidian, exec, monarch-launch-or-focus ^obsidian$ "uwsm-app -- obsidian"' "$HYPR_BINDINGS_FILE"
  fi
fi

monarch-restart-walker
