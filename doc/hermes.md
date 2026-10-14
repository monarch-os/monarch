# Hermes

Hermes is optional. Install and open its desktop app with
`monarch install ai hermes`, or choose the terminal agent with
`monarch default agent hermes`. Choosing it installs the same packages without
opening the desktop app. Installation does not select a default agent unless
the user explicitly chooses one.

## Packaging

Monarch tracks the unmodified AUR recipes `hermes-agent-desktop-bin` and
`hermes-agent-bin`, currently 0.22.0 for x86_64. Their metadata uses `source: aur`
and pins the imported AUR commits so the usual AUR sync can propose updates.
The recipes verify and repackage binaries built by the AUR maintainer's GitHub
CI; these are not binaries published by Nous Research itself. This adds the
maintainer's build infrastructure to the normal AUR trust boundary.

Desktop uses Arch's `electron42` and starts its backend through `/usr/bin/hermes`.
On first installation, Monarch seeds `~/.config/hermes-desktop-flags.conf` with
`--ozone-platform=wayland` for Niri. Existing flags files are preserved.
That packaged CLI uses `/opt/hermes-agent`; Desktop and CLI share the user's
configuration, credentials, sessions and skills. Updates belong to pacman,
not an in-app updater or a source checkout under `~/.hermes/hermes-agent`.
The source variants `hermes-agent` and `hermes-agent-desktop` are also recognized
when already installed and are not replaced automatically.

Monarch always invokes the packaged CLI for this integration, even when an old
`~/.local/bin/hermes` shadows it on PATH. Existing user commands and private
runtime checkouts are preserved; no automatic cleanup or reset is performed.
The former local `hermes-desktop` test package must be removed explicitly before
installing the AUR desktop package because both ship `/usr/bin/hermes-desktop`.

## Desktop integration

Monarch never passes `--yolo` or changes Hermes' safety configuration. An
explicitly enabled Hermes YOLO setting remains the user's choice.

Noctalia renders `~/.hermes/skins/monarch.yaml` from
`~/.config/noctalia/templates/hermes.yaml`. `monarch theme hermes --activate`
retries theme setup when Noctalia was unavailable during installation. It
activates Monarch only when the default profile uses its default skin or Monarch
already; other selected skins, custom Hermes homes and custom profiles are left
unchanged. For an explicit switch on the default profile, run
`/usr/bin/hermes config set display.skin monarch`.

The Niri rule recognizes both `Hermes` and the AUR app id
`com.nousresearch.hermes`, and floats only the window titled `Hermes HUD`. Global shortcuts,
pointer snapping and pinning across workspaces are compositor-dependent;
Hyprland-specific Hermes IPC does not apply to Niri.

`monarch remove ai hermes` removes only the desktop package and clears the
default agent only if it was Hermes. It keeps the runtime package and all
user-owned data. This is not a full uninstall of Hermes.

## Publication checks

Both AUR recipes match their imported commits byte for byte, and both artifacts
pass their declared SHA-256 checksums. The recipes repackage successfully in the
builder container; dependency checks were skipped for that packaging-only test
and the declared dependencies were installed separately in the VM.

In the provisioned, unencrypted Monarch VM, both packages installed and the
readiness probe passed. Desktop opened natively under Wayland, the backend module
resolved to `/opt/hermes-agent/hermes_cli/main.py`, and Ctrl+Shift+H produced a
floating `Hermes HUD` with app id `com.nousresearch.hermes`. The screenshot was
captured and inspected. The earlier private runtime and command were preserved,
and the default agent remained unset. No provider credentials were configured.

The earlier Noctalia Miasma/Nord skin regeneration check remains applicable to
the unchanged template. The packaged CLI activated that skin successfully.

Dependency review remains a rollout check. On 2026-10-15, `npm audit --omit=dev`
against the lock shipped in the AUR runtime artifact reported four high-severity
entries and no critical entries. One entry concerns the locked npm Electron,
which Desktop does not ship: it uses Arch's `electron42`. These results are not
four demonstrated vulnerabilities in the installed app. The previous critical
alert counts referred to the superseded 2026.9.7 workspace lock.
