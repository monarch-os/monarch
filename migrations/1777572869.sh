echo "Restore stock kernel on non-XPS Panther Lake systems"

if monarch-hw-intel-ptl && ! monarch-hw-match "XPS"; then
  monarch-pkg-add linux linux-headers

  for pkg in linux-ptl linux-ptl-headers; do
    sudo pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
  done

  sudo rm -f /etc/limine-entry-tool.d/intel-panther-lake.conf
  sudo rm -f /etc/limine-entry-tool.d/dell-xps-panther-lake.conf

  if monarch-cmd-present limine-update; then
    sudo limine-update
  fi
fi
