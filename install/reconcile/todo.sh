# Upgrade entry point: optional/older packages keep their existing integration.
source "${BASH_SOURCE[0]%/*}/../helpers/todo.sh"

monarch_reconcile_todo() {
  local package name version extra comparison
  # Query the installed package, not a stray executable on PATH. Pacman and
  # vercmp understand package releases and epochs; shell string ordering does not.
  package=$(pacman -Q monarch-todo 2>/dev/null) || return 0
  read -r name version extra <<<"$package"
  [[ $name == "monarch-todo" && -n $version && -z $extra ]] || return 1
  comparison=$(vercmp "$version" "0.2.0") || return
  case $comparison in
    -1) return 0 ;;
    0 | 1) ;;
    *) return 1 ;;
  esac
  [[ -x /usr/bin/monarch-todo ]] || return 0
  /usr/bin/monarch-todo setup-desktop --help >/dev/null 2>&1 || return 0
  monarch_configure_todo "$1"
}
