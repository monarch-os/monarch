# The power profile is now remembered per power source by
# monarch-powerprofiles-set, which runs as the user. The udev rule that used to
# re-apply it has to go: udev runs as root, so the memory it wrote landed in
# /root and never met the user's — which is why it could only ever set a
# hardcoded profile, undoing whatever had been picked from the menu.
rule=/etc/udev/rules.d/99-power-profile.rules

if [[ -f $rule ]]; then
  echo "Removing the root-owned power profile udev rule"
  sudo rm -f "$rule"
  sudo udevadm control --reload 2>/dev/null || true
fi
