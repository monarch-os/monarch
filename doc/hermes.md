# Hermes

Hermes is optional. Install and open its desktop app with
`monarch install ai hermes`, or choose the terminal agent with
`monarch default agent hermes`. Choosing it provisions the same runtime without
opening the desktop app. No other agent preference changes during installation.

The `hermes-desktop` package is currently built for x86_64 only. The installer
prepares upstream's release in `~/.hermes/hermes-agent` and seeds the matching
prebuilt Electron app there. Desktop and CLI share credentials, sessions and
skills. Updates remain available through Hermes itself. Initial setup downloads
the runtime and its dependencies and can take several minutes.

Monarch keeps Hermes approval prompts enabled. It never passes `--yolo` or
changes Hermes' safety configuration. An explicitly enabled Hermes YOLO setting
remains the user's choice.

Noctalia renders `~/.hermes/skins/monarch.yaml` from
`~/.config/noctalia/templates/hermes.yaml`. `monarch theme hermes --activate`
retries theme setup when Noctalia was unavailable during installation. It
activates Monarch only when Hermes uses its default skin or Monarch already;
other selected skins are preserved. For an explicit switch, run
`hermes config set display.skin monarch`. Custom Hermes homes and profile skin
distribution are not managed by this integration.

The Niri rule floats only the window titled `Hermes HUD`. Global shortcuts,
pointer snapping and pinning across workspaces are compositor-dependent;
Hyprland-specific Hermes IPC does not apply to Niri.

Existing commands and checkouts are never reset by Monarch's installer. A
pre-existing Hermes installation must already be usable, or the installer stops
with a repair hint. An interrupted source installation may need repair using
upstream's installer; Monarch does not blindly rerun it over user files. A
complete release runtime whose desktop app has not been seeded can be retried.

`monarch remove ai hermes` removes the desktop package and clears the default
agent only if it was Hermes. It keeps the user-owned runtime, credentials,
sessions and generated skin. This is not a full uninstall of upstream Hermes.

## Publication checks

The x86_64 package builds successfully and its upstream launch/sandbox tests
pass. Monarch's mocked integration tests cover provisioning, retained user
files, agent selection, prompts, skin selection and removal. In the provisioned
Monarch VM, the shared runtime installed, the native Wayland desktop opened its
provider setup page with the Monarch skin, and Noctalia regenerated the skin
when switching between Miasma and Nord. No account or API key was configured,
and the default agent remained unset. HUD behavior still needs live validation.

Do not publish this initial package without reviewing the upstream dependency
alerts. On 2026-10-14, `npm audit --omit=dev` against the release workspace lock
reported 20 affected dependency entries, including two critical entries around
`simple-git` and its argument parser. Desktop's Git review code imports
`simple-git`. These scanner results are not a demonstration of exploitability
in Hermes, but require triage or a corrected upstream release before rollout.
