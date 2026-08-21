# monarch-powerprofiles-set now remembers the profile per source, as the user.
# The rule has to go: udev runs as root, so what it wrote landed in /root and
# never met the user's pick — it could only ever re-apply a hardcoded profile.
rule=/etc/udev/rules.d/99-power-profile.rules

if [[ -f $rule ]]; then
  echo "Removing the root-owned power profile udev rule"
  sudo rm -f "$rule"
  sudo udevadm control --reload 2>/dev/null || true
fi
