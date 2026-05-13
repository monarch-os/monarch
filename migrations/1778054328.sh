echo "Use monarch-system-lock and monarch-system-wake in hypridle (skipped — Monarch no longer ships Hypridle)"

# Hypridle has been replaced by swayidle; this historical migration is now a no-op.
if monarch-cmd-present monarch-refresh-hypridle; then
  monarch-refresh-hypridle
fi
