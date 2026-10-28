source "${BASH_SOURCE[0]%/*}/../helpers/lazyvpn.sh"

monarch_reconcile_lazyvpn() {
  local package name version extra comparison
  package=$(pacman -Q monarch-lazyvpn 2>/dev/null) || return 0
  read -r name version extra <<<"$package"
  [[ $name == "monarch-lazyvpn" && -n $version && -z $extra ]] || return 1
  comparison=$(vercmp "$version" "0.2.0") || return
  case $comparison in
    -1) return 0 ;;
    0 | 1) ;;
    *) return 1 ;;
  esac
  [[ -x /usr/bin/monarch-lazyvpn ]] || return 0
  /usr/bin/monarch-lazyvpn --preview --help >/dev/null 2>&1 || return 0
  monarch_configure_lazyvpn "$1"
}
