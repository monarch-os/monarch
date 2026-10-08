monarch_reconcile_about_branding() {
  local source="$MONARCH_PATH/icon.txt"
  local target="$HOME/.config/monarch/branding/about.txt"
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/monarch/branding/about.sha256"
  local source_hash target_hash previous_hash="" temporary

  [[ -f $source ]] || {
    echo "Missing About branding source: $source" >&2
    return 1
  }
  [[ -L $target ]] && return 0
  [[ ! -e $target || -f $target ]] || return 0

  source_hash=$(sha256sum "$source")
  source_hash=${source_hash%% *}
  if [[ -f $target ]]; then
    target_hash=$(sha256sum "$target")
    target_hash=${target_hash%% *}
    [[ ! -L $state && -f $state ]] && previous_hash=$(<"$state")
    if [[ $target_hash != "$source_hash" && $target_hash != "$previous_hash" ]]; then
      return 0
    fi
  fi

  [[ ! -L $state ]] || {
    echo "Cannot record About branding through a symlink: $state" >&2
    return 1
  }
  monarch_reconcile_managed_file "$source" "$target" || return 1
  [[ ! -f $state || $(<"$state") != "$source_hash" ]] || return 0
  mkdir -p "$(dirname "$state")"
  temporary=$(mktemp "$(dirname "$state")/.about-hash.XXXXXX")
  if printf '%s\n' "$source_hash" >"$temporary" && mv -f "$temporary" "$state"; then
    return 0
  fi
  rm -f "$temporary"
  return 1
}
