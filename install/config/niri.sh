# Deploy and validate the Monarch niri entry-point at ~/.config/niri/config.kdl.
# Fresh installs mark all migrations as already-applied (preflight/migrations.sh),
# so the migration that normally runs monarch-refresh-niri never fires here. Wire
# the canonical deploy+validate path into the install. config.sh (run earlier) has
# already seeded the user-owned includes (noctalia.kdl, user.kdl) into ~/.config/niri/.
monarch-refresh-niri
