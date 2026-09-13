set -euo pipefail

source "$MONARCH_PATH/install/reconcile/config-files.sh"

alacritty="$HOME/.config/alacritty/alacritty.toml"
if [[ -f $alacritty && ! -L $alacritty ]]; then
  legacy_default_sha256=$(sha256sum "$alacritty" | cut -d' ' -f1)
  case "$legacy_default_sha256" in
    5a15d6a6321988ba67917136157344ebe61c687997ddb2c8b03cbcc64c03daf3 | \
      5739e8e39c949b5a2a6a92e53a4f1b94a7a42863b76329e49c19c4b6f88b6c42 | \
      c2e6ff8f390fe2357e29353f3d8469a9df45fd277f8ce1ddc047de26eb3494d6 | \
      89c50d171ea925d9b1c854428f6e56ce2ddc4a13702a55d5e97cf7da7cd73164 | \
      68452eefa068191e149defa9ddf16bfce0d7c69393376afc293495e30a9937e4)
      monarch_reconcile_managed_file \
        "$MONARCH_PATH/config/alacritty/alacritty.toml" "$alacritty"
      ;;
  esac
fi
