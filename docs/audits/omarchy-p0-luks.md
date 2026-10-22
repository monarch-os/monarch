# Omarchy P0 — LUKS keyboard repair

Date: 2026-10-22. Baseline: `0d6010d7a`. Scope: boot keyboard availability.

Plymouth copies `/etc/vconsole.conf` directly, bypassing Monarch's existing
`FILES` exclusion for non-Latin primary layouts. The managed
`monarch_vconsole.conf` drop-in guards that copy independently of customized
`monarch_hooks.conf`. Latin layouts and explicit administrator `FILES` entries
are preserved. A consistency test prevents the independent layout lists drifting.

System reconciliation rebuilds affected existing images through Limine, or
classic mkinitcpio when Limine is unavailable. Failed commands and Limine's
status-zero per-kernel errors remain retryable. Success state is machine-wide,
guard-digest based, and rejects writable or symbolic state paths.

Active presets with `ALL_config` or `<preset>_config` require administrator review:
mkinitcpio's `-c` disables the drop-ins even for `/etc/mkinitcpio.conf`. This check
runs before trusting an existing success marker. Unsupported presets neither
rebuild images nor update success state, and their configuration is preserved.

## Validation

Fixtures cover repeated sourcing, hook-local `FILES`, inherited keyboard
variables, version-sorted configuration precedence, explicit presets, retries,
and unsafe state paths. The current `monarch-settings` recipe automatically
packages the guard without a `backup` exemption that could leave it in `.pacnew`.

No actual initramfs was rebuilt. Installed-package and encrypted-boot acceptance
remain outstanding; the dev VM was unavailable. The full baseline integration
suite has unrelated network and Windows VM mount-boundary failures, reproduced
without this change.

Source: [Omarchy 4.0.6](https://github.com/omacom/omarchy/releases/tag/v4.0.6).
