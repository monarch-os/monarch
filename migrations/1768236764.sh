echo "Prevent kernel upgrades from making current modules unavailable"

monarch-pkg-add kernel-modules-hook
sudo systemctl enable --now linux-modules-cleanup.service
