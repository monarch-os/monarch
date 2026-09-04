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

A schema bump changes which input states are supported. Permanent invariants
stay in `system.sh` and `user.sh`; historical transformations live under
`schema/<from>-to-<to>/` and run only while crossing that boundary. Once the
older schema is no longer supported, its whole transition directory can be
deleted.

A bump is not required for an additive managed file, a newly seeded file, or an
idempotent invariant that works for every supported schema.
