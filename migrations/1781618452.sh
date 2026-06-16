echo "Convert the monarch-todo/lazyvpn niri integration to per-feature include files"

# The first cut appended each feature's keybind as its own `binds {}` block to
# ~/.config/niri/user.kdl. Niri allows only one `binds {}` per FILE, so a machine
# with both installed had its ENTIRE user.kdl rejected — breaking every override.
# Fix: each feature gets a dedicated kdl file with its own `binds {}` block, pulled
# in by a one-line include. Niri merges binds across files, so blocks never clash.
NIRI_DIR="$HOME/.config/niri"
USER_KDL="$NIRI_DIR/user.kdl"

if [[ -f "$USER_KDL" ]]; then
  # Drop any existing marker block (old inline-binds form or already-converted).
  for marker in todo lazyvpn; do
    sed -i "/\/\/ monarch:${marker}:begin/,/\/\/ monarch:${marker}:end/d" "$USER_KDL"
  done

  if monarch-pkg-present monarch-todo; then
    cat >"$NIRI_DIR/monarch-todo.kdl" <<'KDL'
// Managed by `monarch install todo` — removed by `monarch remove todo`.
binds {
    Mod+T hotkey-overlay-title="Todo" { spawn "monarch-launch-tui" "monarch-todo"; }
}
window-rule {
    match app-id="org.monarch.monarch-todo"
    open-floating true
    default-column-width { fixed 760; }
    default-window-height { fixed 560; }
}
KDL
    printf '\n// monarch:todo:begin\ninclude "./monarch-todo.kdl"\n// monarch:todo:end\n' >>"$USER_KDL"
  fi

  if monarch-pkg-present monarch-lazyvpn; then
    cat >"$NIRI_DIR/monarch-lazyvpn.kdl" <<'KDL'
// Managed by `monarch install lazyvpn` — removed by `monarch remove lazyvpn`.
binds {
    Mod+Ctrl+V hotkey-overlay-title="LazyVPN controls" { spawn "monarch-launch-floating-terminal-with-presentation" "monarch-lazyvpn"; }
}
KDL
    printf '\n// monarch:lazyvpn:begin\ninclude "./monarch-lazyvpn.kdl"\n// monarch:lazyvpn:end\n' >>"$USER_KDL"
  fi

  if pgrep -x niri >/dev/null 2>&1; then
    niri msg action load-config-file >/dev/null 2>&1 || true
  fi
fi
