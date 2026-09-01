monarch_reconcile_managed_file() {
  local source="$1"
  local target="$2"
  local target_dir temporary

  [[ -f $source ]] || {
    echo "Missing managed config source: $source" >&2
    return 1
  }

  target_dir=$(dirname "$target")
  mkdir -p "$target_dir"
  cmp -s "$source" "$target" 2>/dev/null && return 0

  temporary=$(mktemp "$target_dir/.monarch-managed.XXXXXX")
  if cp -p "$source" "$temporary" && mv -f "$temporary" "$target"; then
    return 0
  fi

  rm -f "$temporary"
  return 1
}

monarch_reconcile_seeded_file() {
  local source="$1"
  local target="$2"

  [[ -e $target || -L $target ]] && return 0
  monarch_reconcile_managed_file "$source" "$target"
}

monarch_reconcile_managed_tree() {
  local source="$1"
  local target="$2"
  local parent name staging previous

  [[ -d $source ]] || {
    echo "Missing managed config tree: $source" >&2
    return 1
  }

  parent=$(dirname "$target")
  name=$(basename "$target")
  mkdir -p "$parent"
  staging=$(mktemp -d "$parent/.${name}.new.XXXXXX")
  previous=$(mktemp -d "$parent/.${name}.old.XXXXXX")
  rmdir "$previous"

  if ! cp -a "$source/." "$staging/"; then
    rm -rf "$staging"
    return 1
  fi

  if [[ -e $target || -L $target ]]; then
    if ! mv "$target" "$previous"; then
      rm -rf "$staging"
      return 1
    fi
  else
    previous=""
  fi

  if mv "$staging" "$target"; then
    [[ -z $previous ]] || rm -rf "$previous"
    return 0
  fi

  [[ -z $previous ]] || mv "$previous" "$target"
  rm -rf "$staging"
  return 1
}
