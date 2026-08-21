# udev runs as root, so the per-source memory it wrote landed in /root and never
# met the user's pick: the rule could only ever re-apply a hardcoded profile.
rule=/etc/udev/rules.d/99-power-profile.rules

if [[ -f $rule ]]; then
  echo "Removing the root-owned power profile udev rule"
  sudo rm -f "$rule"
  sudo udevadm control --reload 2>/dev/null || true
fi
