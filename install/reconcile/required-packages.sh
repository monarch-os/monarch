set -euo pipefail

source "$MONARCH_PATH/install/helpers/package-manifest.sh"

packages=()
monarch_load_package_manifest packages "$MONARCH_PATH/install/monarch-base.packages" required
((${#packages[@]})) || {
  echo "The required package manifest is empty" >&2
  exit 1
}

declare -A installed=()
while IFS= read -r package; do
  installed["$package"]=true
done < <(pacman -Qq)

missing=()
for package in "${packages[@]}"; do
  [[ -v installed[$package] ]] || missing+=("$package")
done

((${#missing[@]} == 0)) || monarch-pkg-add "${missing[@]}"
