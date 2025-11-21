# Show installation environment variables
gum log --level info "Installation Environment:"

env | grep -E "^(MONARCH_CHROOT_INSTALL|MONARCH_ONLINE_INSTALL|MONARCH_USER_NAME|MONARCH_USER_EMAIL|USER|HOME|MONARCH_REPO|MONARCH_REF|MONARCH_PATH)=" | sort | while IFS= read -r var; do
  gum log --level info "  $var"
done
