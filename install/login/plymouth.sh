if [[ $(plymouth-set-default-theme) != "monarch" ]]; then
  sudo cp -r "$HOME/.local/share/monarch/default/plymouth" /usr/share/plymouth/themes/monarch/
  sudo plymouth-set-default-theme monarch
fi
