# Development tasks

Read the matching sections before editing. Technical contracts live in the [development reference](../../docs/development.md); common security and simplicity rules remain in [AGENTS.md](../../AGENTS.md).

- **Commands in `bin/`**: read [naming](../../docs/development.md#command-naming), [metadata](../../docs/development.md#command-metadata) and [helpers](../../docs/development.md#helper-commands). Keep public metadata in English and within the first 80 lines. Update browsable groups in the router without exposing hidden-only groups.
- **Shell aliases and functions**: read [helper descriptions](../../docs/development.md#shell-helper-descriptions), update `default/shells/command-descriptions.tsv` in the same change, then run `bash test/shell.d/shell-helpers-test.sh`.
- **Installation and upgrades**: read [install scripts](../../docs/development.md#install-scripts) and [reconciliation](../../docs/development.md#reconciliation). Separate privileged and user/session ownership, preserve idempotence and verify that failure leaves the previous usable state intact before cleanup.
- **Configuration and themes**: read [config structure](../../docs/development.md#config-structure), [theming](../../docs/development.md#theming) and [refresh](../../docs/development.md#refresh-pattern). Use Noctalia's ownership and templates. Refresh only the intended relative config path; use `monarch-refresh-niri` for Niri.
- **Menus and plugins**: read [menu contracts](../../docs/development.md#menu) and the desktop/plugin constraints under [upstream sync](../../docs/development.md#upstream-sync). Update menu data and translations rather than the renderer for new rows. Reserve aliases for established alternate names needed for compatibility. Validate with `bin/monarch-menu --check` and the relevant menu tests.
- **Upstream integrations**: read [product decisions](../../docs/product-decisions.md) and [upstream sync](../../docs/development.md#upstream-sync). Preserve intentional divergences; do not restore Hyprland, Quickshell, the old theme engine or timestamped migrations.

Use the [testing guide](testing.md) to select validation. For visual work, apply the change in a running development desktop, capture with `monarch capture screenshot fullscreen save`, and inspect the result as well as running automated tests.
