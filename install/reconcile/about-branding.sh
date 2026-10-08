about_branding_source="$MONARCH_PATH/icon.txt"
about_branding_target="$HOME/.config/monarch/branding/about.txt"
about_branding_state="${XDG_STATE_HOME:-$HOME/.local/state}/monarch/branding/about.sha256"
about_branding_previous_hash=""

[[ -f $about_branding_source ]] || {
  echo "Missing About branding source: $about_branding_source" >&2
  return 1
}
[[ -L $about_branding_target ]] && return 0
[[ ! -e $about_branding_target || -f $about_branding_target ]] || return 0

about_branding_source_hash=$(sha256sum "$about_branding_source")
about_branding_source_hash=${about_branding_source_hash%% *}
if [[ -f $about_branding_target ]]; then
  about_branding_target_hash=$(sha256sum "$about_branding_target")
  about_branding_target_hash=${about_branding_target_hash%% *}
  [[ ! -L $about_branding_state && -f $about_branding_state ]] && about_branding_previous_hash=$(<"$about_branding_state")
  if [[ $about_branding_target_hash != "$about_branding_source_hash" && $about_branding_target_hash != "$about_branding_previous_hash" ]]; then
    return 0
  fi
fi

[[ ! -L $about_branding_state ]] || {
  echo "Cannot record About branding through a symlink: $about_branding_state" >&2
  return 1
}
monarch_reconcile_managed_file "$about_branding_source" "$about_branding_target" || return 1
[[ ! -f $about_branding_state || $(<"$about_branding_state") != "$about_branding_source_hash" ]] || return 0
mkdir -p "$(dirname "$about_branding_state")"
about_branding_temporary=$(mktemp "$(dirname "$about_branding_state")/.about-hash.XXXXXX")
if printf '%s\n' "$about_branding_source_hash" >"$about_branding_temporary" && mv -f "$about_branding_temporary" "$about_branding_state"; then
  return 0
fi
rm -f "$about_branding_temporary"
return 1
