source "${BASH_SOURCE[0]%/*}/noctalia-wait.sh"

monarch_noctalia_enable_plugins() {
  local plugin status=0 config enabled

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
