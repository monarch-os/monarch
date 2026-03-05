echo "Add SUPER+ALT+SHIFT+F shortcut to open nautilus in cwd"

# Add the new CWD binding if it doesn't exist
if ! grep -q "CTRL ALT SHIFT, F" ~/.config/hypr/bindings.conf; then
  sed -i '/bindd = CTRL ALT SHIFT, F, File manager, exec, uwsm-app -- nautilus --new-window/a bindd = SUPER ALT SHIFT, F, File manager (cwd), exec, uwsm-app -- nautilus --new-window "$(monarch-cmd-terminal-cwd)"' ~/.config/hypr/bindings.conf
fi
