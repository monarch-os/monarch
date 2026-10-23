set -euo pipefail

monarch-pkg-present disktree-bin && monarch-cmd-present disktree || exit 0

launcher="$HOME/.local/share/applications/Disk Usage.desktop"
[[ -f $launcher && ! -L $launcher ]] || exit 0
read -r digest _ < <(sha256sum "$launcher")
# Retire only the shipped dua launcher; custom launchers remain user-owned.
if [[ $digest == "b97491fc7ec0c01a7b6943b941203bc8037b620f6d19e92c7e3c12cce3bcb5cb" ]]; then
  rm -- "$launcher"
fi
