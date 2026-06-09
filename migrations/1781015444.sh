echo "Replace tmux with herdr (agent-aware multiplexer) and theme it via Noctalia"

# Swap the package: pull herdr in, drop tmux (no-op if tmux was never installed).
monarch-pkg-add herdr-bin
monarch-pkg-drop tmux

# Deposit the herdr Noctalia user-template. Inputs live under
# ~/.config/noctalia/templates/ (copied wholesale on fresh install); upgraders
# need it placed explicitly. Noctalia renders it to ~/.config/herdr/config.toml.
mkdir -p ~/.config/noctalia/templates
cp -f "$MONARCH_PATH/config/noctalia/templates/herdr.toml" ~/.config/noctalia/templates/herdr.toml

# Register [templates.herdr] in the user-templates registry if absent.
TEMPLATES=~/.config/noctalia/user-templates.toml
if [[ -f $TEMPLATES ]] && ! grep -q '\[templates.herdr\]' "$TEMPLATES"; then
  cat >> "$TEMPLATES" << 'EOF'

[templates.herdr]
input_path = "~/.config/noctalia/templates/herdr.toml"
output_path = "~/.config/herdr/config.toml"
post_hook = "herdr server reload-config 2>/dev/null || true"
EOF
fi

# Drop the now-orphaned tmux config.
rm -rf ~/.config/tmux

# Force Noctalia to re-render its templates so ~/.config/herdr/config.toml exists
# immediately (otherwise herdr falls back to its built-in defaults until the next
# color generation). Best-effort: no-op when Noctalia is not running.
qs -c noctalia-shell ipc call wallpaper refresh >/dev/null 2>&1 || true
