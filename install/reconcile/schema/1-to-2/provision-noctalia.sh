set -euo pipefail

source "$MONARCH_PATH/install/reconcile/noctalia-wait.sh"

state="$HOME/.local/state/monarch/reconcile/1-to-2/noctalia-refreshed"
if [[ ! -f $state ]]; then
  monarch-refresh-noctalia
  mkdir -p "$(dirname "$state")"
  printf '%s\n' complete >"$state.tmp"
  mv "$state.tmp" "$state"
fi

if monarch_noctalia_wait 50; then
  monarch-provision-first-run
fi
