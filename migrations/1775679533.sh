echo "Add Exegol Elephant menu and Walker keybindings"

# Link the Exegol Elephant menu plugin
mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_exegol.lua ~/.config/elephant/menus/monarch_exegol.lua

# Add monarchExegol Walker keybindings if not already present
if ! grep -q 'menus:monarchExegol' ~/.config/walker/config.toml; then
  cat >> ~/.config/walker/config.toml << 'EOF'

"menus:monarchExegol" = [
  { action = "menus:default", label = "shell/start", default = true, bind = "Return" },
  { action = "stop", label = "stop", bind = "ctrl s", after = "AsyncClearReload" },
  { action = "remove", label = "remove", bind = "ctrl d"},
  { action = "open file browser", label = "workspace", bind = "ctrl o" },
  { action = "firefox", label = "firefox", bind = "ctrl f" },
  { action = "bloodhound", label = "bloodhound", bind = "ctrl b" },
]
EOF
fi

# Update exegol config: disable shell logging by default
if [ -f ~/.exegol/config.yml ]; then
  sed -i 's/always_enable: True/always_enable: False/' ~/.exegol/config.yml
fi

monarch-restart-walker
