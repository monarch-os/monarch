set -euo pipefail

source "$MONARCH_PATH/install/helpers/package-manifest.sh"

packages=()
monarch_load_package_manifest packages "$MONARCH_PATH/install/monarch-base.packages" required
((${#packages[@]})) || {
  echo "The required package manifest is empty" >&2
  exit 1
}

declare -A requested=()
for package in "${packages[@]}"; do
  requested["$package"]=true
done

declare -A installed=()
while IFS= read -r package; do
  installed["$package"]=true
done < <(pacman -Qq)

modules=${MONARCH_MODULES_PATH:-/usr/lib/modules}
shopt -s nullglob
pkgbase_files=("$modules"/*/pkgbase)
shopt -u nullglob
if ((${#pkgbase_files[@]})); then
  while IFS= read -r package; do
    kernel=${package%-headers}
    if [[ $kernel == linux-cachyos || $kernel == linux-cachyos-* ]] &&
      [[ -v installed[$kernel] && ! -v requested[$package] ]]; then
      packages+=("$package")
      requested["$package"]=true
    fi
  done < <(MONARCH_MODULES_PATH="$modules" "$MONARCH_PATH/bin/monarch-hw-kernel-headers")
fi

missing=()
for package in "${packages[@]}"; do
  [[ -v installed[$package] ]] || missing+=("$package")
done

((${#missing[@]} == 0)) || monarch-pkg-add "${missing[@]}"
