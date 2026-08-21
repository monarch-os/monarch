# The install runs offline against a mirror that has no pre-Turing driver, and
# first-run's sudoers grant does not cover pacman — so report it, don't retry it.
if [[ -f ~/.local/state/monarch/nvidia-driver-pending ]]; then
  monarch-notification-send "󰢮" "NVIDIA driver not installed" \
    "Your GPU needs a driver the offline installer does not carry. Run: monarch install nvidia" \
    -u critical
fi
