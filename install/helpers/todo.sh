# Current desktop setup, shared by installation and reconciliation. This helper
# requires the package to be installed; upgrade eligibility belongs to reconcile.
monarch_configure_todo() {
  local root=$1 niri_dir="$HOME/.config/niri" user_kdl="$HOME/.config/niri/user.kdl"
  local target="$niri_dir/monarch-todo.kdl" source="$root/default/monarch/todo/monarch-todo.kdl"

  [[ -f $source ]] || return 1
  /usr/bin/monarch-todo setup-desktop || return
  mkdir -p "$niri_dir"

  if [[ -f $target ]] && ! cmp -s "$source" "$target"; then
    [[ -e $target.pre-panel ]] || cp -p "$target" "$target.pre-panel"
  fi
  cmp -s "$source" "$target" 2>/dev/null || cp "$source" "$target"

  touch "$user_kdl"
  if ! grep -Eq '^[[:space:]]*include[[:space:]]+"\./monarch-todo\.kdl"' "$user_kdl"; then
    cat >>"$user_kdl" <<'EOF'

// monarch:todo:begin
include "./monarch-todo.kdl"
// monarch:todo:end
EOF
  fi
  if [[ -n ${NIRI_SOCKET:-} ]] && pgrep -u "$(id -u)" -x niri >/dev/null 2>&1; then
    niri validate && niri msg action load-config-file
  fi
}
