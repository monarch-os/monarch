set -euo pipefail

installed=$(pacman -Qq)
legacy=()
for package in dua-cli dust; do
  if grep -qxF "$package" <<<"$installed"; then
    legacy+=("$package")
  fi
done
(( ${#legacy[@]} > 0 )) || exit 0

monarch-pkg-add disktree-bin
pacman -Qk --quiet disktree-bin
timeout 10 disktree --help >/dev/null
# Do not cascade into dependent packages or prune unrelated dependencies.
for package in "${legacy[@]}"; do
  monarch-pkg-drop --keep-dependencies "$package"
done
