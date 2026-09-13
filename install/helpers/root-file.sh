source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

monarch_install_root_file() {
  local source="$1" destination="$2" mode="$3"
  local stage prefix suffix

  prefix="${destination%/*}/.${destination##*/}.monarch."
  stage=$(as_root /usr/bin/mktemp -- "${prefix}XXXXXX") || return 1
  suffix=${stage#"$prefix"}
  if [[ $stage != "$prefix"* || ! $suffix =~ ^[[:alnum:]]{6}$ ]]; then
    return 1
  fi

  if as_root /usr/bin/install -m "$mode" -o root -g root -T "$source" "$stage" &&
    as_root /usr/bin/mv -Tf -- "$stage" "$destination"; then
    return 0
  fi

  [[ $stage == "$prefix"* && $suffix =~ ^[[:alnum:]]{6}$ ]] &&
    as_root /usr/bin/rm -f -- "$stage"
  return 1
}
