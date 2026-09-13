set -euo pipefail

source "$MONARCH_PATH/install/reconcile/config-files.sh"

kitty="$HOME/.config/kitty/kitty.conf"
if [[ -f $kitty && ! -L $kitty ]]; then
  legacy_default_sha256=$(sha256sum "$kitty" | cut -d' ' -f1)
  if [[ $legacy_default_sha256 == 0cb2131c21332a602db00fb53a16c4295c76541e0d7ea54f421212493356a67a ]]; then
    monarch_reconcile_managed_file \
      "$MONARCH_PATH/config/kitty/kitty.conf" "$kitty"
  fi
fi
