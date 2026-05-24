echo "Switch Niri config to include-based loader (no more generated config.kdl)"

# The first Hyprland → Niri migration generated a fully-inlined config.kdl by
# concatenating templates. That tripped Niri's "duplicate top-level section"
# rule whenever the user override re-declared `layout`. The new layout splits
# the defaults across multiple files and uses Niri's native `include`
# directive — config.kdl is now a tiny stable loader.
#
# This migration: redeploy the loader for users who already ran the previous
# migration. (Niri focus-ring/border colours now come from Noctalia's built-in
# niri template, not from a Monarch-rendered niri-colors.kdl.)

if command -v monarch-refresh-niri >/dev/null 2>&1; then
  monarch-refresh-niri || true
fi
