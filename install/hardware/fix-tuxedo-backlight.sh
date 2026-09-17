dmi_vendor=${MONARCH_DMI_VENDOR_PATH:-/sys/class/dmi/id/sys_vendor}
modprobe_dir=${MONARCH_MODPROBE_DIR:-/etc/modprobe.d}
modules=${MONARCH_MODULES_PATH:-/lib/modules}

if grep -Eqi "TUXEDO|Slimbook" "$dmi_vendor" 2>/dev/null; then
  mapfile -t headers < <(monarch-hw-kernel-headers)
  monarch-pkg-add "${headers[@]}" tuxedo-drivers-nocompatcheck-dkms

  # clevo_xsm_wmi claims the same WMI GUIDs and blocks the keyboard backlight.
  mkdir -p "$modprobe_dir"
  echo "blacklist clevo_xsm_wmi" >"$modprobe_dir/blacklist-clevo-xsm-wmi.conf"

  # Old manual installs may leave an unowned conflicting module behind.
  for f in "$modules"/*/extra/clevo-xsm-wmi.ko; do
    if [[ -f $f ]]; then
      rm "$f"
    fi
  done
fi
