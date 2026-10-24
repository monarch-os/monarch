# Tasks integration ownership

The optional `monarch-todo` package owns its backend, Noctalia plugin, translations,
desktop entry and reminder service. Their source and tests live in the
`monarch-os/monarch-todo` repository (`doc/panel.md`, `test/panel.py`,
`test/desktop.py`). Monarch must not seed a second copy of that plugin or enable
it unconditionally in its Noctalia defaults.

Monarch owns only `monarch install/remove todo`, its bar indicator, and
the Super+T include. Installation and reconciliation use `install/helpers/todo.sh`
for current setup; the installer never sources a reconciliation entry point.
Reconciliation alone checks whether an optional/older backend is eligible.
The helper calls `monarch-todo setup-desktop` before updating the shortcut.
Package setup registers a user symlink to the packaged
plugin, backs up legacy seeded copies and enables the packaged reminder unit.
Package installation hooks do not write into user homes.
Super+T and the indicator invoke `monarch-todo panel` directly, without a Monarch launcher.

Validate Monarch's boundary with `bash test/monarch-todo-test.sh`. Run panel,
backend and desktop migration tests in the `monarch-todo` checkout. Publish its
v0.2.0 release before advancing the recipe's source tag; panel/backend upgrades
then occur in a single package transaction.
