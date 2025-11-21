# Install all base packages
mapfile -t packages < <(grep -v '^#' "$MONARCH_INSTALL/python.packages" | grep -v '^$')

# Ne need for offline install if there is internet
if [[ -n ${MONARCH_ONLINE_INSTALL:-} ]]; then
    pipx install "${packages[@]}"
else
    pipx install "${packages[@]}" --pip-args="--no-index --find-links=/var/cache/python/offline"
fi