# Install all base packages
mapfile -t packages < <(grep -v '^#' "$MONARCH_INSTALL/monarch-base.packages" | grep -v '^$')
monarch-pkg-add "${packages[@]}"
