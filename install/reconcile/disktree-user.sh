set -euo pipefail

monarch-pkg-present disktree-bin && monarch-cmd-present disktree || exit 0

launcher="$HOME/.local/share/applications/Disk Usage.desktop"
[[ -f $launcher && ! -L $launcher ]] || exit 0
read -r digest _ < <(sha256sum "$launcher")
if [[ $digest != "b97491fc7ec0c01a7b6943b941203bc8037b620f6d19e92c7e3c12cce3bcb5cb" ]]; then
  content=$(<"$launcher")
  content=${content//"Icon=$HOME/.local/share/applications/icons/Disk Usage.png"/"Icon=disk-usage"}
  read -r digest _ < <(printf '%s\n' "$content" | sha256sum)
  case "$digest" in
    5bd2175639c11e0b3c3bbcd2f1425f38ece0d50b725baaf4650a8045ee2527e3 | 18903a200e4426ec3a16d85eafa82d3bdde88a331301df13f3712866f06da422) ;;
    *) exit 0 ;;
  esac
fi
rm -- "$launcher"
