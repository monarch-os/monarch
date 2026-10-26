source "${BASH_SOURCE[0]%/*}/noctalia-wait.sh"

monarch_noctalia_reconcile_overview() {
  local config line in_shell=false
  config=$(noctalia config export merged) || return
  while read -r line; do
    case "$line" in
      "[shell]") in_shell=true ;;
      \[*) in_shell=false ;;
      *)
        if [[ $in_shell == "true" && $line =~ ^niri_overview_close_on_launch_enabled[[:space:]]*= ]]; then
          return 0
        fi
        ;;
    esac
  done <<<"$config"
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
