set -euo pipefail

legacy_root="$HOME/.local/share/monarch"
legacy_noctalia="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
if [[ -d $legacy_root && ! -L $legacy_root ]] ||
  [[ -d $legacy_noctalia && ! -L $legacy_noctalia ]]; then
  finalize_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
  hook_dir=$(dirname "$finalize_hook")
  mkdir -p "$hook_dir"
  hook_tmp=$(mktemp "$hook_dir/.packaged-runtime.XXXXXX")
  trap 'rm -f "$hook_tmp"' EXIT
  install -m 0755 "$MONARCH_PATH/install/reconcile/packaged-runtime.sh" "$hook_tmp"
  mv -fT "$hook_tmp" "$finalize_hook"
  trap - EXIT
fi
