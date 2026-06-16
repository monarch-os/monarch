echo "Re-arm monarch-todo reminders via a oneshot systemd --user service; refresh the bar widget icon"

# monarch-todo reminder timers are transient systemd --user timers: a reboot
# drops them, so a reminder could show in the TUI yet never fire. The store's
# `reminder` field is the source of truth; `monarch-todo reload-reminders`
# re-creates missing timers (and fires any missed). A oneshot service runs it at
# every session start — only when monarch-todo is installed (its niri include
# file is present).
TODO_KDL="$HOME/.config/niri/monarch-todo.kdl"
if [[ -f "$TODO_KDL" ]]; then
  # Drop the earlier niri spawn-at-startup approach if it was ever added.
  sed -i '/spawn-at-startup "monarch-todo" "reload-reminders"/d' "$TODO_KDL"

  SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_USER_DIR"
  cat >"$SYSTEMD_USER_DIR/monarch-todo-reminders.service" <<'EOF'
[Unit]
Description=Re-arm monarch-todo reminder timers from the store
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/bin/monarch-todo reload-reminders

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable monarch-todo-reminders.service 2>/dev/null || true

  # One-time re-arm now (best-effort; needs a monarch-todo build with the
  # reload-reminders subcommand — a no-op on older binaries).
  monarch-todo reload-reminders >/dev/null 2>&1 || true

  # Refresh the Noctalia bar widget icon to format-list-checkbox.
  NOCTALIA_CFG="$HOME/.config/noctalia/settings.json"
  if command -v jq >/dev/null && [[ -f "$NOCTALIA_CFG" ]]; then
    tmp=$(mktemp)
    if jq '(.bar.widgets.left, .bar.widgets.center, .bar.widgets.right) |=
             ((. // []) | map(if .textCommand? == "monarch-todo bar" then .icon = "format-list-checkbox" else . end))' \
         "$NOCTALIA_CFG" >"$tmp"; then
      mv "$tmp" "$NOCTALIA_CFG"
    else
      rm -f "$tmp"
    fi
  fi
fi
