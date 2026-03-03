echo "Add Logout option to system menu"

monarch-refresh-sddm

if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
  sudo sed -i 's/^Current=.*/Current=monarch/' /etc/sddm.conf.d/autologin.conf
fi
