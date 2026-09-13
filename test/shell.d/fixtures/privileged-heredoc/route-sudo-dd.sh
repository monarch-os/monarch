sudo dd status=none of=/etc/monarch/boot.conf <<EOF
cmdline=$boot_params
EOF
