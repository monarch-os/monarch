source "${BASH_SOURCE[0]%/*}/noctalia-wait.sh"

monarch_noctalia_reconcile_overview() {
  local defined
  defined=$(python3 - <<'PY'
import os
from pathlib import Path
import tomllib

home = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config') / 'noctalia'
state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'noctalia/settings.toml'
paths = sorted(config.glob('*.toml'))
if state.exists():
  paths.append(state)
documents = [tomllib.loads(path.read_text()) for path in paths]
print('yes' if any('niri_overview_close_on_launch_enabled' in document.get('shell', {})
                  for document in documents) else 'no')
PY
  ) || return

  [[ $defined == "no" ]] || return 0
  noctalia msg config-set shell.niri_overview_close_on_launch_enabled true
}

monarch_noctalia_enable_plugins() {
  local plugin status=0 config enabled

  monarch_noctalia_reconcile_overview || return
  config=$(noctalia config export full) || return
  enabled=$(python3 -c '
import sys
import tomllib
print("\n".join(tomllib.loads(sys.stdin.read()).get("plugins", {}).get("enabled", [])))
' <<<"$config") || return

  for plugin in monarch/indicators monarch/agents monarch/menu monarch/wifi-qr monarch/network monarch/display monarch/theme monarch/first-steps monarch/crashes; do
    # Enabling even an active local plugin can browse uncached remote catalogs.
    grep -Fxq "$plugin" <<<"$enabled" && continue
    noctalia msg plugins enable "$plugin" || status=$?
  done

  (( status == 0 )) || return "$status"
  noctalia msg config-reload
}
