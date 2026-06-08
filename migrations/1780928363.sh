echo "Drop yt6801-dkms (the CachyOS kernel now covers the Motorcomm YT6801)"

# yt6801-dkms was an [omarchy]-only out-of-tree DKMS driver for the Motorcomm
# YT6801 NIC (Slimbook Executive), installed unconditionally via the package
# list. Mainline merged the in-tree dwmac-motorcomm driver in Linux 7.0 (binds
# PCI 1f0a:6801), so the CachyOS kernel handles the YT6801 natively — the DKMS
# module is now redundant, can no longer be updated once [omarchy] is gone, and
# keeping it risks shadowing the native driver. Drop it (no-op if absent).

monarch-pkg-drop yt6801-dkms
