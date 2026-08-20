stop_install_log

echo_in_style() {
  echo "$1" | tte --canvas-width 0 --anchor-text c --frame-rate 640 print
}

clear
echo
tte -i "$MONARCH_PATH"/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
echo

# Display installation time if available
if [[ -f $MONARCH_INSTALL_LOG_FILE ]] && grep -q "Total:" "$MONARCH_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  TOTAL_TIME=$(tail -n 20 "$MONARCH_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [[ -n $TOTAL_TIME ]]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo_in_style "Finished installing"
fi

if sudo test -f /etc/sudoers.d/99-monarch-installer; then
  sudo rm -f /etc/sudoers.d/99-monarch-installer &>/dev/null
fi

# Exit gracefully if user chooses not to reboot. An unattended install has
# nobody to answer, and gum reads the TTY, so it would hang here forever — take
# the reboot path, which is what the drive asked for by installing at all.
if [[ -n ${MONARCH_UNATTENDED:-} ]] || gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  if [[ -n ${MONARCH_CHROOT_INSTALL:-} ]]; then
    touch /var/tmp/monarch-install-completed
    exit 0
  else
    sudo reboot 2>/dev/null
  fi
fi
