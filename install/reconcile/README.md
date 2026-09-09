# Configuration ownership

Reconciliation converges supported installations onto the current packaged
state. It does not replay a permanent history of releases.

Every file written below the user's home must have one ownership model:

- **Managed file:** Monarch owns the complete file and may replace it on every
  reconciliation. Use `monarch_reconcile_managed_file`.
- **Managed tree:** Monarch owns one dedicated directory. Use
  `monarch_reconcile_managed_tree`; never target a directory shared with user or
  third-party data.
- **Seeded file:** Monarch supplies the initial contents, then the user owns the
  file. Use `monarch_reconcile_seeded_file`.
- **User file:** Monarch preserves it. When a format change is unavoidable,
  apply a narrow idempotent transformation in `user.sh`.
- **Generated file:** Rebuild it from its user-owned source through the command
  that owns the format, such as `monarch-refresh-niri`.

Noctalia merges `~/.config/noctalia/*.toml`, so new Monarch-owned settings
should normally live in a dedicated managed fragment rather than overwrite the
user's configuration. Its palette directory and plugin root are shared: manage
individual palette files and Monarch's own plugin subdirectories only.

Managed trees are compared by contents, entry types, symlink targets and Unix
permissions before staging a replacement. Timestamps and ownership do not
trigger a copy: packaged sources belong to root, installed copies to the user.
Changed trees still use staged replacement and rollback, including removal of
obsolete files inside the owned directory.

`noctalia-activation.sh` owns the plugin inventory and activation/reload sequence.
Reconciliation probes readiness once, first-run waits up to 60 seconds and the
deferred hook up to 30 seconds. Failed enablement or reload stays retryable;
first-run reports failure and deferred activation retains its hook.

A schema bump changes which input states are supported. Permanent invariants
stay in `system.sh` and `user.sh`; historical transformations live under
`schema/<from>-to-<to>/` and run only while crossing that boundary. Once the
older schema is no longer supported, its whole transition directory can be
deleted.

A bump is not required for an additive managed file, a newly seeded file, or an
idempotent invariant that works for every supported schema.

User finalization distinguishes new accounts from initialized installations:
schema state, V4 migration state, an ongoing `1-to-2` transition or an existing
`finalize-user` marker prevents replaying initial user setup. Finalization still
repairs skill links; first-run installs session integrations and retries failed
steps on the next login. `--force` repeats this convergence; `--first-install`
explicitly selects initial setup. Keyring initialization only seeds missing
files, including when a new installation retries after a later step failed.

The V4 transition seeds `noctalia/monarch-v4.toml` with compatible palette,
dark/light and idle preferences. Bar position uses the existing user-owned
`zz-monarch-bar-position.toml`, so the bar command reads the migrated position.
Zero timeouts and disabled idle stay disabled; custom idle commands are carried
as data, never executed by migration. Existing fragments and Noctalia's mutable
settings are not overwritten. The [Noctalia configuration layers](https://docs.noctalia.dev/noctalia/configuration/)
let later UI choices override these seeded preferences.

Compatible V4 `<scheme>/<scheme>.json` palettes move to the V5 palette directory.
Modified versions of shipped palettes receive a collision-free `V4-` prefix,
so subsequent managed-palette updates cannot overwrite them. The original
Noctalia files are still archived; retries can read that archive. Unsupported
V4 settings, QML plugins and templates are not automatically translated. Invalid
settings keep the transition pending instead of silently discarding preferences.

Herdr keeps customized files; only the recognized stock V4 template output is
replaced. Fastfetch only changes the stock legacy theme-reading command inside
JSON strings, preserving other modules and comments. Changed app files get a
`.bak.monarch-v5` original before atomic replacement. Existing app symlinks are
left alone and reported for manual adaptation; missing configs are seeded.

`windows-vm.sh` owns Windows VM detection, migration orchestration and legacy
cleanup. It runs as the login user and uses the shared operations in
`monarch-windows-vm`, elevating only the verified packaged helper. The helper
recognizes that user's stock Compose container, disables
automatic restart, migrates the protected compose and verifies the live mounts
and web protection. An active VM may restart with a two-minute graceful shutdown;
a stopped or absent container stays stopped or absent. Custom containers are
left untouched with an error, and failed convergence retains the legacy compose
for retry. A protected journal preserves the intended activity state across a
partial replacement; an explicit stop cancels it. Disks, shared files and
legitimate source symlinks are preserved.
