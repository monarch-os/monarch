echo "Re-arm monarch-todo reminders at login (spawn-at-startup reload-reminders)"

# monarch-todo reminder timers are transient systemd --user timers: a reboot
# drops them, so a reminder could show in the TUI yet never fire. The store's
# `reminder` field is the source of truth; `monarch-todo reload-reminders`
# re-creates missing timers (and fires any missed). Run it at every login via
# niri spawn-at-startup, added to the per-feature include file.
TODO_KDL="$HOME/.config/niri/monarch-todo.kdl"
if [[ -f "$TODO_KDL" ]]; then
  if ! grep -q 'spawn-at-startup "monarch-todo" "reload-reminders"' "$TODO_KDL"; then
    printf '%s\n' 'spawn-at-startup "monarch-todo" "reload-reminders"' >>"$TODO_KDL"
  fi
  # One-time re-arm now (best-effort; needs a monarch-todo build with the
  # reload-reminders subcommand — a no-op on older binaries).
  monarch-todo reload-reminders >/dev/null 2>&1 || true
fi
