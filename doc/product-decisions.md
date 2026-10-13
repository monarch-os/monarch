# Monarch product decisions

Monarch adopts upstream features when they improve a desktop workflow. Preserve
these choices when syncing Omarchy or extending desktop integrations. Runtime
conventions live in [AGENTS.md](../AGENTS.md), and security invariants live in
[SECURITY.md](../SECURITY.md).

## Desktop defaults

Keep the default bar quiet. Weather and active-window titles are opt-in because
they add persistent information and can expose location or private titles.
Automatic weather location must be an explicit user choice.
The privacy indicator, microphone keybindings and native audio panel cover the
default microphone workflow without another permanent widget.

Use Noctalia's native audio, media, clipboard and plugin-management surfaces.
Add Monarch UI only for a demonstrated gap in a useful workflow. Clock presets
with seconds require efficient refresh limited to the surfaces that need it.

Captive-portal assistance completes the existing network panel. Use
NetworkManager's connectivity state and open a fixed HTTP probe only on an
explicit sign-in action. Never execute a portal-provided URL or send saved
credentials.

Limited connectivity is a failed or stale connectivity check, not proof of a
captive portal. Offer an explicit NetworkManager recheck without reconnecting
the link; reserve browser sign-in for the `portal` connectivity state.

The network panel manages Ethernet connections and offers an explicit Wi-Fi
rescan alongside automatic scans. Internet priority changes IPv4 and IPv6 route
metrics in currently connected Ethernet/Wi-Fi profiles that already have a default
route: 50 for the preferred connection, 600 for its fallbacks. These settings
persist in those profiles; Auto restores NetworkManager's automatic metrics
(-1), not earlier custom values. Do not change VPN routing, local-only profiles,
gateways or disconnected profiles. Reapply without tearing down connections.

Keep connection actions ahead of diagnostics. Hide virtual and unmanaged
interfaces in the panel, label connect/disconnect actions explicitly, and show
saved Internet priority separately from the route currently in use. Statistics,
Wi-Fi band and DNS live in a secondary details view, opened directly with
`noctalia msg panel-open monarch/network:panel details`.

Details show every connected physical Ethernet/Wi-Fi interface, including
local-only links, with all assigned IPv4/IPv6 addresses and default gateways.
Label IPv6 link-local addresses and distinguish the active Internet output;
latency and throughput remain scoped to that output, not to every interface.

## Compositor workflows

- Preserve Monarch's screenshot capture and editing pipeline. A second default
  route to the compositor's screenshot UI would bypass that workflow. Users
  can bind native actions themselves.
- Generic window-layout persistence remains deferred. A supported restore needs
  stable window identity, application launch information and a reliable restore
  contract. Any experiment rearranging already-open windows must expose its
  best-effort behavior and matching conflicts.
- Keep generic picture-in-picture rules. The Google Meet title heuristic stays
  outside the defaults because it can also match the main meeting window.

## Software selection

| Software | Choice and reason |
| --- | --- |
| `mpv-mpris` | Included so the default video player participates in Noctalia's media controls. |
| `dua-cli` | Included with its launcher so disk usage is a discoverable desktop tool. |
| `udiskie` | Outside the defaults while the existing removable-media stack meets the need. Reconsider after a reproduced automount failure. |
| `yt-dlp` | Optional software. Browser extension and native-messaging integration require a separate product and security decision. |
| Docker QEMU binfmt | Optional because system-wide foreign-architecture emulators are unnecessary for most desktop users. |
| Moonlight | Keep the optional installer and removal flow. Client support does not imply a Sunshine server integration. |
| `hey-cli` | Excluded as an unwanted Basecamp product integration. |

## Package conflicts

An interactive update may retry a package conflict so the user can answer
Pacman's replacement question. An unattended update stops when an answer is
needed. Filesystem conflicts stop the update and preserve the live files;
Pacman's error output does not authorize moving system state into quarantine.

## Excluded integrations

ONCE, Dropbox and Hermes will not be integrated into Monarch.

## Deferred integrations

A Fireworks balance collector remains deferred until a documented API gives
ordinary user credentials reliable access to the required usage data.

Sunshine remains a separate future integration, with its own installation,
configuration and removal decisions.
