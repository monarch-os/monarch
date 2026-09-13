set -euo pipefail

retired_packages=()
if [[ -f $HOME/.local/bin/claude && -x $HOME/.local/bin/claude ]]; then
  retired_packages+=(claude-code)
fi
if [[ -f $HOME/.local/bin/codex && -x $HOME/.local/bin/codex ]]; then
  retired_packages+=(openai-codex)
fi
if [[ -f $HOME/.local/bin/opencode && -x $HOME/.local/bin/opencode ]]; then
  retired_packages+=(opencode)
fi
((${#retired_packages[@]} == 0)) || monarch-pkg-drop "${retired_packages[@]}"

state="$HOME/.local/state/monarch/reconcile/1-to-2/system-after-user"
mkdir -p "$(dirname "$state")"
printf '%s\n' complete >"$state.tmp"
mv "$state.tmp" "$state"
