# Monarch Welcome

First-run welcome panel for Monarch, packaged as a Noctalia plugin.

Replaces the previous toast-stack onboarding with a single centered modal that
guides the user through the keybinding cheatsheet, Wi-Fi setup, system update,
and Voxtype install.

## Triggers

- **First boot** — `monarch-first-run` calls `qs -c noctalia-shell ipc call plugin:monarch-welcome open`.
- **On demand** — the `monarch welcome` (`bin/monarch-welcome`) command opens the
  same panel at any time.

## Layout

- `manifest.json` — plugin descriptor (Noctalia >= 4.0.0).
- `Main.qml` — IPC handler + status checks (online, Voxtype installed).
- `Panel.qml` — the welcome UI (header + four step cards + footer).

Shipped under `config/noctalia/plugins/monarch-welcome/` in the Monarch repo and
symlinked into `~/.config/noctalia/plugins/monarch-welcome/` by
`monarch-refresh-noctalia` / the install migration.
