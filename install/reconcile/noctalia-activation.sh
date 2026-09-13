source "${BASH_SOURCE[0]%/*}/noctalia-wait.sh"

monarch_noctalia_enable_plugins() {
  local plugin status=0

  for plugin in monarch/indicators monarch/agents monarch/menu monarch/wifi-qr monarch/network monarch/display monarch/theme; do
    noctalia msg plugins enable "$plugin" || status=$?
  done

  (( status == 0 )) || return "$status"
  noctalia msg config-reload
}
