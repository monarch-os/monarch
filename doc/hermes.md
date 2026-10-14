# Hermes

Hermes is optional. `monarch default agent hermes` installs only the CLI
(`hermes-agent-bin`) and selects it as the terminal agent.
`monarch install ai hermes` installs Desktop (`hermes-agent-desktop-bin`), letting
pacman install its runtime dependency, and opens it without changing the default agent.
Existing AUR source variants are recognized and preserved.

## Packaging

Monarch tracks the unmodified AUR binary recipes through its normal AUR sync.
The artifacts are built by the AUR maintainer's GitHub CI, not published by
Nous Research itself. Desktop uses Arch's `electron42` and `/usr/bin/hermes`,
whose runtime lives in `/opt/hermes-agent`. Both packages are updated by pacman.

The integrated terminal agent also invokes `/usr/bin/hermes` explicitly so an
older user CLI cannot redirect it. Existing private runtime checkouts and user
commands are preserved. The former local `hermes-desktop` test package must be
removed before installing the AUR Desktop because they share a launcher path.

## Desktop integration

Monarch seeds `~/.config/hermes-desktop-flags.conf` with
`--ozone-platform=wayland` only when no flags file exists. The Niri rule recognizes
`Hermes` and `com.nousresearch.hermes` and floats only the `Hermes HUD` window.

Hermes manages its own appearance. Desktop defaults to following the system's
light/dark preference; Monarch does not generate or activate a custom skin.
Palette synchronization with Noctalia is deferred. Monarch does not enable YOLO
or change Hermes configuration.

`monarch remove ai hermes` removes Desktop and its unneeded dependencies through
pacman. A runtime installed only as a dependency is removed; an explicitly
installed CLI is kept. Selecting Hermes as the terminal agent marks its runtime
explicit, including when Desktop installed it first. Credentials, sessions and
other user data remain. The default agent is cleared only if Hermes was selected
and its runtime is no longer installed.

## Validation

The AUR 0.22.0 artifacts passed their recipe checksums and repackaged successfully
in the builder container. Both packages installed in the provisioned Monarch VM.
Desktop opened under Wayland and Ctrl+Shift+H produced a floating `Hermes HUD`;
the screenshot was inspected. The backend resolved to `/opt/hermes-agent`.
No provider credentials were configured.

Integration tests cover separate CLI/Desktop installation, source variants,
installation/removal failures, preserving user data and flags, prompt forwarding
and dependency-aware removal.

Dependency review remains a rollout check: the workspace lock shipped in the
AUR runtime reported four high-severity npm entries and no critical entries on
2026-10-15. The locked npm Electron entry does not describe the system Electron
used by Desktop; these findings do not establish installed-app exploitability.
