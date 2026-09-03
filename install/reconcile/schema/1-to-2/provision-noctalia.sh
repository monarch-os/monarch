set -euo pipefail

state="$HOME/.local/state/monarch/reconcile/1-to-2/noctalia-refreshed"
if [[ ! -f $state ]]; then
  monarch-refresh-noctalia
  mkdir -p "$(dirname "$state")"
  printf '%s\n' complete >"$state.tmp"
  mv "$state.tmp" "$state"
fi

for _ in $(seq 1 50); do
  noctalia msg status >/dev/null 2>&1 && break
  sleep 0.1
done

if noctalia msg status >/dev/null 2>&1; then
  monarch-provision-first-run
fi
