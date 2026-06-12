if [[ $(plymouth-set-default-theme) != "monarch" ]]; then
  sudo cp -r "$MONARCH_PATH/default/plymouth" /usr/share/plymouth/themes/monarch/
  sudo plymouth-set-default-theme monarch
fi
