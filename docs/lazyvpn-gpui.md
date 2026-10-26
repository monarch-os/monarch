# LazyVPN graphical integration

LazyVPN 0.2.0 replaces its terminal interface with GPUI. The command name and
`monarch-lazyvpn-status` output stay compatible with scripts and the status pill.

## Ownership

- The LazyVPN package ships the binaries, `monarch-lazyvpn.desktop` and the
  data-only Noctalia template at `/usr/share/monarch-lazyvpn/noctalia/lazyvpn.json`.
- `install/helpers/lazyvpn.sh` configures both new and existing installations:
  `niri/monarch-lazyvpn.kdl`, its include in `niri/user.kdl`, and
  `noctalia/lazyvpn.toml`, under the user's XDG config directory.
- Niri opens app-id `monarch-lazyvpn` floating at 880 × 540. Mod+Ctrl+V starts the
  native binary directly. Noctalia renders the live palette to
  `$XDG_CONFIG_HOME/monarch-lazyvpn/theme.json`.
- Changed integration files receive a one-time `.pre-gpui` backup. The legacy
  `LazyVPN.desktop` is backed up and removed only when its command matches the
  old managed terminal launcher. Profile and credential files are not migrated.
- The indicator probes `--preview --help`: older packages keep their terminal
  launcher. A failed native launch is not retried through a terminal.

## Rollout order

1. Merge the LazyVPN frontend and publish its `v0.2.0` source tag, including the
   lockfile, desktop entry and Noctalia template.
2. Merge the `monarch-pkgs` recipe for 0.2.0. Its source is that tag, so it cannot
   build before the tag exists. Publish through the package-builder nightly or
   its manual workflow, not a local repository sync.
3. Ship this Monarch integration and run the normal update/reconciliation flow.
   `install/reconcile/lazyvpn.sh` skips absent or older packages and checks the
   native CLI capability before configuring anything. Repeated runs converge
   without adding duplicate includes. An incomplete new package fails before
   the old launcher is removed.

The application version is a release prerequisite, not a Monarch schema change.
No timestamped migration or schema bump is needed. If Monarch arrives first,
the old integration remains usable until a later reconciliation after the VPN
package upgrade. Fresh installation requires the new package.

## Verification

```bash
bash test/monarch-lazyvpn-test.sh
bash test/monarch-cli-test.sh
bin/monarch commands --check
niri validate --config default/monarch/lazyvpn/niri/monarch-lazyvpn.kdl
noctalia plugins lint default/noctalia/plugins/monarch-indicators
```

The LazyVPN integration test isolates HOME, XDG directories and package tools.
It covers missing/old/incomplete packages, repeated configuration, backup and
profile preservation, installation/removal failures and the actual indicator
callback for both frontend generations.
