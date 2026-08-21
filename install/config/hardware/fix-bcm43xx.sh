# Install Wi-Fi drivers for Broadcom chips found in some MacBooks, as well as other systems:
# - BCM4360 (2013–2015 MacBooks)
# - BCM4331 (2012, early 2013 MacBooks)

pci_info=$(lspci -nn)

if (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "BCM4360 / BCM4331 detected"
  # broadcom-wl is prebuilt against the stock linux kernel and hard-depends on
  # it, so it pulled a second kernel in and could never load on the cachyos one.
  monarch-pkg-add broadcom-wl-dkms dkms linux-cachyos-headers
fi
