# Q21 / P2 product decisions

Research date: 2026-09-11. The local Quattro comparison point is
`omarchy/quattro@a703092631599de5e70c5d3d2be4fbb268f8639b`; the compositor
contract checked here is Niri v26.04 (`8ed0da4`), and the shell contract is
Noctalia v5.1.0 (`c7b9197af77ff22bfb9a83c52a95643a1d90ca86`). This note separates observed
capabilities from product choices. A Quattro feature is evidence of intent, not
evidence that its Hyprland implementation belongs in Monarch.

## Decision matrix

| Candidate | Primary evidence and factual limit | P2 decision |
| --- | --- | --- |
| Niri window-layout save/restore | Niri exposes current windows and partial layout geometry, but window/workspace IDs last only for the current compositor lifetime. Its action API has no save/restore transaction; several column actions operate on focus, so replay is multi-step and race-prone. [`Window`](https://github.com/niri-wm/niri/blob/v26.04/niri-ipc/src/lib.rs#L1251), [`WindowLayout`](https://github.com/niri-wm/niri/blob/v26.04/niri-ipc/src/lib.rs#L1304), [`Workspace`](https://github.com/niri-wm/niri/blob/v26.04/niri-ipc/src/lib.rs#L1358), [requests/actions](https://github.com/niri-wm/niri/blob/v26.04/niri-ipc/src/lib.rs#L12) | **Do not ship generic persistence.** At most prototype an explicitly labelled, best-effort rearranger for windows that are already open. Revisit when Niri provides a stable session/layout contract. |
| Keyboard screenshot targeting | Niri has an interactive screenshot UI and direct screen/window actions. The native UI accepts normal compositor move/resize actions, but it is a movable rectangular selection, not Quattro's Tab/arrow window cycler. `screenshot-window` can target a current window ID. [v25.05 notes](https://github.com/niri-wm/niri/discussions/1589), [v26.04](https://github.com/niri-wm/niri/releases/tag/v26.04), [IPC actions](https://github.com/niri-wm/niri/blob/v26.04/niri-ipc/src/lib.rs#L216) | **Do not add a separate default route.** It duplicates the existing capture workflow while bypassing Monarch's editor pipeline. The native action remains available for a user binding; an exact window list can later use a launcher plus `screenshot-window --id` if semantic targeting becomes necessary. |
| Active-window bar item | Noctalia v5.1 already supplies `active_window`, showing the focused app icon/title on the current output. [documentation](https://docs.noctalia.dev/noctalia/bar/widgets/active-window/), [implementation](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/shell/bar/widgets/active_window_widget.cpp) | **Available, off by default.** It adds persistent title noise and can expose private titles during sharing; users can enable the built-in without Monarch code. |
| Weather | Noctalia v5.1 already has bar and desktop weather surfaces backed by its shared weather service; it is disabled by default and requires a position. Automatic location/geocoding uses `api.noctalia.dev`; manual coordinates avoid that step, while forecasts use Open-Meteo. [weather service](https://docs.noctalia.dev/noctalia/services/weather/), [location](https://docs.noctalia.dev/noctalia/services/location/), [implementation](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/system/weather_service.cpp) | **Keep opt-in.** Prefer Noctalia's native service for users who enable weather; make automatic location an explicit privacy choice. |
| Dedicated microphone widget | The native `volume` widget supports `device = "input"`, mute state, `hide_when_inactive`, and microphone IPC. The `privacy` widget already reports active microphone capture. [volume](https://docs.noctalia.dev/noctalia/bar/widgets/volume/), [privacy](https://docs.noctalia.dev/noctalia/bar/widgets/privacy/), [implementation](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/shell/bar/widgets/volume_widget.cpp) | **No additional default item.** Existing privacy indication, mic keybind/OSD, and audio panel cover the default case. Document the built-in input-volume variant for users wanting a permanent control. |
| Richer media | Noctalia v5.1 natively provides artwork and metadata, player selection/pinning, seek, previous/next, repeat, shuffle and visualizer in MPRIS surfaces, plus media IPC. [widget](https://docs.noctalia.dev/noctalia/bar/widgets/media/), [control center](https://docs.noctalia.dev/noctalia/control-center/), [implementation](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/shell/control_center/tabs/media_tab.cpp) | **Use the native surfaces; do not fork them.** Add `mpv-mpris` so Monarch's default `mpv` participates. |
| Captive portal | Noctalia v5.1 listens to NetworkManager's connectivity-change signal but retains/exposes no Portal/Limited/Full state and has no sign-in UX. (`noctalia.portalAvailable()` means XDG Desktop Portal, not Wi-Fi portal.) [network service](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/dbus/network/network_manager_service.cpp), [network types](https://github.com/noctalia-dev/noctalia/blob/c7b9197af77ff22bfb9a83c52a95643a1d90ca86/src/dbus/network/network_types.h). Quattro commit [`41a40ccc`](https://github.com/basecamp/omarchy/commit/41a40ccc78b60c9698a0e45dc358f0e4b5ffd5a3) reads Portal/Limited state and opens a fixed HTTP probe only on user action. | **Accept as a separate Monarch network-panel capability.** Consume NetworkManager state, never scrape an arbitrary redirect, and open a fixed HTTP endpoint only after an explicit click. |
| Generic PiP | Monarch already floats titles matching `Picture.?in.?[Pp]icture` in `default/niri/windows.kdl`. Niri officially documents this pattern and supports size/position rules, but not sticky/pinned windows across workspaces. [window-rule example](https://github.com/niri-wm/niri/blob/main/docs/wiki/Configuration%3A-Window-Rules.md), [FAQ](https://github.com/niri-wm/niri/blob/main/docs/wiki/FAQ.md), [sticky request #932](https://github.com/niri-wm/niri/issues/932) | **Keep and refine the generic native rule.** Size/position parity is reasonable; promise no Quattro-style pinning until Niri implements it. |
| Google Meet PiP heuristic | Quattro commit [`1e2a3156`](https://github.com/basecamp/omarchy/commit/1e2a3156a91d86049116f3282fb9a4df23d662f1) floats/pins Chromium windows titled `Meet - …`. Niri cannot supply the pinning part; a changing title can also match the main meeting window. | **Do not add by default.** Keep it as an optional user rule pending validation of browser app-id/title behavior. |
| Fireworks usage | No Noctalia v5.1 built-in or catalogued official/community plugin exists. Quattro's collector was introduced in [`77cf58cc`](https://github.com/basecamp/omarchy/commit/77cf58ccfecc5103041a0a437e1401308f237b7d); its [`README`](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/shell/plugins/agents/README.md) says live balance is permission-gated and console API keys could not call it. Monarch's `monarch-agents` already discovers collectors. [official catalog](https://github.com/noctalia-dev/official-plugins/blob/4a888beef245bc316d805ffdcaccdb0944b92031/catalog.toml) | **Defer the collector.** The integration seam is ready, but a default balance display is not trustworthy until Fireworks exposes a reliable user API. |
| Hermes | No Noctalia v5.1 built-in/catalogued integration exists; this is an app/CLI lifecycle decision outside the shell. Quattro added Hermes in [`a12a21c0`](https://github.com/basecamp/omarchy/commit/a12a21c02fbc945ac1de73633494df67908ae28a), including agent selection and a desktop wrapper. Official Hermes docs say the desktop shares CLI state/runtime and is launched/built with `hermes desktop`; Linux installation is a remote installer. [desktop](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md), [overview/install](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/index.mdx) | **Optional, not a P2 default.** Add an agent adapter only after Monarch owns a reviewable package/update/removal path; preserve the shared `~/.hermes` data if later adopted. |
| `udiskie` | Quattro commit [`ddd7e058`](https://github.com/basecamp/omarchy/commit/ddd7e058a22f33e21635cbe590276c0580ee4416) added removable-drive automount. Current Quattro starts `udiskie --automount --no-notify --no-tray` from [`default/hypr/autostart.lua`](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/default/hypr/autostart.lua). Monarch already ships the same UDisks2/GVfs/Nautilus stack, and its current installed session provides the expected removable-media behavior without `udiskie`. | **Do not add by default.** There is no reproduced product gap to justify a second automount client. Revisit only with a cold-plug failure that the existing stack cannot handle. |
| `mpv-mpris` | Quattro added the small MPRIS bridge in [`961d4241`](https://github.com/basecamp/omarchy/commit/961d4241f0016636439f082705a9fa2ce1e135c9). Monarch already installs `mpv` (`install/monarch-base.packages`) and enables Noctalia media. | **Add by default.** It completes an existing default-player/default-shell contract rather than adding a new surface. |
| `yt-dlp` | Quattro commit [`e5290b0a`](https://github.com/basecamp/omarchy/commit/e5290b0a12c556cf2bbecb01e3441605dce4d602) couples the package to a Chromium native-messaging download extension; its browser manual assigns Alt+Shift+D. [browser manual](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/manual/23-browsers.md) | **Optional package only.** Do not restore a browser native-messaging host as part of P2; that is a separate security/product decision. |
| `dua-cli` | Quattro switched its disk-usage app to `dua i /` in [`9cf18525`](https://github.com/basecamp/omarchy/commit/9cf1852525a5f7de26d3162db9d61e2f5c1d5523); the current launcher is [`applications/Disk Usage.desktop`](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/applications/Disk%20Usage.desktop). | **Add only with the launcher/menu entry.** A latent CLI package alone does not deliver the Quattro user feature. |
| Docker QEMU binfmt | Quattro PR [#6231](https://github.com/basecamp/omarchy/pull/6231) states the goal: multi-architecture Docker builds by default. The Arch package `qemu-user-static-binfmt` depends on the much larger `qemu-user-static`; Monarch already ships Docker but most users do not build foreign-architecture images. [Arch package](https://archlinux.org/packages/extra/any/qemu-user-static-binfmt/) | **Keep optional.** Provide an explicit multi-arch setup path; do not impose system-wide emulators/format handlers on every desktop. |

## Why generic layout restore is not a native Niri feature

### Established facts

- A Niri snapshot can observe app ID, title, PID, workspace, floating state and
  partial tile geometry. The geometry fields are optional and Niri explicitly
  says they may be absent.
- Window and workspace IDs are runtime handles, not persistent identities.
  There is no launch command or stable app-instance key in a window record, so
  two terminals or dynamic browser titles cannot be matched reliably after a
  restart.
- Some replay operations accept a window ID, while column ordering/display
  operations act on the focused column. Niri also warns that IPC requests are
  processed independently and intervening state may change. A multi-window
  restore is therefore neither atomic nor deterministic.
- The API does not expose a complete saved-session model (including a stable
  identity, app launch command, full column/tab state and a restore operation).
  The upstream request for complete session restoration remains an ecosystem
  discussion, not a released contract. [discussion #4180](https://github.com/niri-wm/niri/discussions/4180)

### Product conclusion

Calling a script “Niri-native save/restore” would overstate its guarantees. If
later prototyped, its persisted format must be versioned, matching conflicts
must be shown rather than guessed, and the command must say “best effort”. P2
should not make that experiment a supported Monarch workflow.

## Screenshot scope

### Established facts

Monarch's current `bin/monarch-capture-screenshot` derives rectangles from
`niri msg`, then uses `slurp`/`grim` and the configured editor. Quattro's
keyboard picker is compositor-specific: commit
[`366c708e`](https://github.com/basecamp/omarchy/commit/366c708e4417fd17e64c6aba72a30c46e2904894)
adds next/previous/directional window selection, and Hyprland layer-scoped binds
route Tab, Shift-Tab, arrows and Return while `slurp` owns focus. Its current
behavior is documented in
[`manual/12-screenshots-recording.md`](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/manual/12-screenshots-recording.md).

Niri's native UI instead lets existing move/resize keybinds manipulate the
selection; Enter saves and Ctrl+C copies. That supplies keyboard operation, but
not semantic window cycling. Noctalia v5's own documented region screenshot is
drag-selected and includes a rich annotation editor; it does not document a
keyboard window target selector. [Noctalia screenshot IPC](https://docs.noctalia.dev/noctalia/ipc/media-and-ui/)

### Product conclusion

Do not add a default shortcut for Niri's native UI. Its rectangular selector
adds little beside Monarch's existing explicit modes and does not preserve the
post-capture editor behavior. Users can bind the native action themselves. If
semantic selection later becomes mandatory, a launcher listing current Niri
windows is safer than emulating Hyprland's temporary input layer.

## Noctalia ownership boundary

Noctalia v5.1 already owns active-window, weather, input volume/mute, privacy and
MPRIS presentation. Its documented plugin runtime can run processes and HTTP
requests, but plugins are an extension seam, not a reason to fork native
surfaces. The plugin API does not expose toplevel/window rules, MPRIS,
NetworkManager or a secrets vault, and plugins are trusted rather than
sandboxed. [runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/),
[plugin security model](https://docs.noctalia.dev/noctalia/plugins/)
The P2 default should remain quiet: enable native surfaces when they complete a
core workflow, and leave informational or account-specific additions opt-in.

Captive-portal assistance is the exception because it completes the existing
network workflow. The safe Quattro design is worth copying at the product level:
use NetworkManager's connectivity classification, show state, and make sign-in
an explicit action to one fixed HTTP probe. Do not execute a portal-provided URL
or send saved credentials.

## Package evidence

The Quattro package baseline at the comparison commit lists all five packages
in
[`install/omarchy-base.packages`](https://github.com/basecamp/omarchy/blob/a703092631599de5e70c5d3d2be4fbb268f8639b/install/omarchy-base.packages).
Monarch's `install/monarch-base.packages` currently includes Docker and `mpv`,
but not `udiskie`, `mpv-mpris`, `yt-dlp`, `dua-cli`, or QEMU binfmt. Package
presence alone does not explain product intent; the linked introduction commits,
autostart and launcher files above do. The resulting P2 package set is therefore
`mpv-mpris`, plus `dua-cli` together with its visible app entry; `udiskie`,
`yt-dlp`, and QEMU binfmt remain outside the default install.

## P2 implementation scope

- Add `mpv-mpris` to the required media stack.
- Install `dua-cli` by default and expose it through a launcher entry that
  disappears when the command is absent.
- Implement captive-portal state and the explicit sign-in action separately in
  the existing Monarch network panel.
