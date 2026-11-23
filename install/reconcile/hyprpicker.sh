set -euo pipefail

marker=${MONARCH_HYPRPICKER_RETIREMENT_MARKER:-/var/lib/monarch/reconcile/hyprpicker-removed}

record_retirement() {
  local marker_dir stage

  marker_dir=${marker%/*}
  [[ ! -L $marker_dir && ( ! -e $marker_dir || -d $marker_dir ) ]] || {
    echo "Invalid hyprpicker retirement state directory: $marker_dir" >&2
    return 1
  }
  install -d -m 0755 "$marker_dir"
  stage=$(mktemp "$marker_dir/.hyprpicker-removed.XXXXXX")
  chmod 0644 "$stage"
  mv -fT "$stage" "$marker"
}

if [[ -f $marker && ! -L $marker ]]; then
  exit 0
elif [[ -e $marker || -L $marker ]]; then
  echo "Invalid hyprpicker retirement marker: $marker" >&2
  exit 1
fi

if query_output=$(LC_ALL=C pacman -Qq hyprpicker 2>&1); then
  [[ $query_output == "hyprpicker" ]] || {
    echo "Unexpected hyprpicker package query result: $query_output" >&2
    exit 1
  }

  if pacman -R --print hyprpicker >/dev/null 2>&1; then
    pacman -R --noconfirm hyprpicker
  else
    echo "hyprpicker has dependents and was left installed." >&2
  fi
else
  query_status=$?
  if (( query_status != 1 )) ||
    [[ $query_output != "error: package 'hyprpicker' was not found" ]]; then
    printf '%s\n' "$query_output" >&2
    exit "$query_status"
  fi
fi

record_retirement
