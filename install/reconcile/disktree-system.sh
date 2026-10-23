set -euo pipefail

installed=$(pacman -Qq)
grep -qxF dua-cli <<<"$installed" || exit 0

pacman -S --needed --noconfirm disktree-bin
[[ $(pacman -Qq disktree-bin) == "disktree-bin" ]] || {
  echo "Disktree is not installed; keeping dua-cli." >&2
  exit 1
}
pacman -Qk --quiet disktree-bin
timeout 10 disktree --help >/dev/null
# Do not cascade into packages depending on dua or prune unrelated dependencies.
pacman -R --noconfirm dua-cli
