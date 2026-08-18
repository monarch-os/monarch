# Noctalia v5 — migration TODO

State of the `noctalia-v5` branch and what is left on it.

Noctalia v5 is a native C++ Wayland shell: no Qt, no Quickshell. v4 is frozen, so
this migration is forced rather than opportunistic. The package is `extra/noctalia`
in the Arch official repos, so there is no packaging work — the binary is
`noctalia`, the daemon is `noctalia -d`, and IPC is `noctalia msg <verb>`.

Branch status: 12 commits, 62 files, +1438 / −2851 vs `dev`. Nothing pushed.
Tests 58/58, `bin/monarch commands --check` OK on 256 commands.

---

## Blocking before merge

### 1. No migration for existing v4 installs

Only fresh installs are covered today. An existing v0.x machine upgrading into
this branch keeps its v4 `~/.config/noctalia/settings.json`, which v5 ignores
entirely, and gets none of the v5 config. Needs a migration under `migrations/`
(create with `monarch-dev-add-migration --no-edit`) that at minimum:

- drops the obsolete v4 files it can identify (`settings.json`, `plugins.json`,
  the `templates/` user-template dir, `~/.cache/noctalia/shell-state.json` and
  `wallpapers.json` — all inert under v5)
- seeds `config.toml` + `palettes/Monarch.json` (`monarch-refresh-config`)
- enables the two bundled plugins (`noctalia msg plugins enable monarch/indicators`
  and `monarch/agents`) — discovery is not activation, a discovered plugin stays
  disabled, which is what `install/first-run/welcome.sh` already handles for fresh
  installs
- carries over the fingerprint toggle into `monarch-fingerprint.toml` when
  `~/.local/state/monarch/fingerprint-enabled` exists

This is the largest remaining gap and the one that breaks real machines.

### 2. Per-scheme wallpaper directory pinning

v4 repointed `wallpaper.directory` at the active scheme's background folder on
every color change (`monarch-theme-apply`). v5 exposes no IPC for it: there is
`wallpaper-set`, `wallpaper-get`, `wallpaper-next/previous/random`, but nothing
that moves the picker's source folder. Options, none verified yet:

- write `[wallpaper] directory` into a Monarch-owned `.toml` and
  `noctalia msg config-reload` (the same trick used for the fingerprint toggle;
  reload is verified to apply config changes live)
- or accept a single shared backgrounds folder and drop the per-scheme behaviour

Related to item 7 below — decide them together.

---

## Deferred by choice

### 3. Firefox / pywalfox template

Explicitly set aside. No v5 blocker known; it is simply not started.

---

## New features requested

Three net-new features modelled on Omarchy quattro, detailed below against the
actual `basecamp/omarchy@quattro` source.

### The architectural catch, read this first

**Omarchy quattro's shell is QML/Quickshell. Noctalia v5 is native C++ with Luau
plugins.** Quattro dropped waybar and now ships its own shell under `shell/`
(`shell.qml`, `Commons/`, `Ui/`, `services/`, `plugins/`), configured by
`~/.config/omarchy/shell.json`.

So the two projects took opposite bets at the same moment: Omarchy moved *to*
Quickshell, Noctalia moved *away* from it. **Nothing below can be ported — every
item is a reimplementation** against Noctalia's Luau plugin API, whose ceiling we
already know (API level 23, no argument arrays, declarative `ui.*` tree only).

That ceiling is the deciding factor for items 5 and 6, and the reason to do 4
first: it is the one that fits comfortably inside it.

### 4. Status indicators: do-not-disturb, night mode, … — *done, verified in VM*

Shipped as three `monarch/indicators` entries — `dnd`, `caffeine`,
`nightlight` — in the bar's **centre** lane, each hidden unless its state is on.
Quattro's `Reminder.qml` maps onto `monarch/indicators:todo`, already shipped.

**Why not the stock widgets.** v5 does have `caffeine`, `nightlight` and
`notifications` widget types (the full list is `active-window audio-visualizer
battery bluetooth brightness caffeine clipboard clock control-center
custom-button keyboard-layout launcher lock-keys media network nightlight
notifications power-profile privacy screenshot session settings spacer sysmon
taskbar text theme-mode tray volume wallpaper weather workspaces`), and they
were tried first. They are always visible and accept **no settings at all** —
probed by feeding candidate keys to `noctalia config validate`, which *does*
report unknown `[widget.<id>]` keys: every `hide_when_*` was rejected on
`caffeine` and `nightlight`, and `notifications` accepts only
`hide_when_no_unread` (unread count, not DND). Nothing there can express
"show only when active".

**The state problem, and the shape that solves it.** A plugin can only render
what it can read, and v5 will not report caffeine or forced night light: no
status verb (`noctalia msg --help` on a live shell is authoritative), nothing in
`~/.local/state/noctalia/settings.toml`, no DBus (`dev.noctalia.Debug` exposes
only verbose-logging control, `dev.noctalia.Mpris` only media), and
`caffeine-enable` takes the wayland idle-inhibit path so it is not in
`systemd-inhibit --list` either.

So Monarch owns the state, following the `omarchy-toggle-idle` shape: the
`monarch-toggle-*` command is both the toggle and the source of truth, gains
`[toggle|on|off|status]` subcommands, and prints `{"enabled":…,"tooltip":…}` on
`status`. The indicator polls that one command every 2s and knows nothing else —
`indicator.pollToggle()` in the plugin is shared by all three. DND needs no
bookkeeping at all, since `notification-dnd-status` reports the real thing.

Consequences worth knowing:

- caffeine and forced night light are tracked in `$XDG_RUNTIME_DIR/monarch/`,
  not `~/.local/state/monarch/toggles/`: they mirror live shell state and must
  die with the session, since a fresh shell always starts with both off.
  `monarch-restart-noctalia` clears them for the same reason
- the control center's caffeine, nightlight and notification shortcuts are
  **removed** from `[[control_center.shortcuts]]`, which keeps only wifi,
  bluetooth and power_profile. For caffeine and night light this is
  correctness — a toggle from there would desync the indicator until the next
  `monarch-toggle-*` call re-converged it. DND could not drift, and is dropped
  for consistency. Every path now goes through the commands: `Mod+Ctrl+I`,
  `Mod+Ctrl+N`, `Mod+Ctrl+Comma` (rewired from raw `notification-dnd-toggle`
  IPC to `monarch-toggle-notification-silencing`), `monarch menu toggle`, and
  the pill itself while it is on. Notification *history* is untouched — it is a
  control center sidebar tab, not a shortcut tile. The array is restated in
  full, since arrays of tables are replaced across `.toml` files, not merged
- quattro's hover-reveal of *inactive* indicators is still not reproduced, and
  cannot be from a plugin — but hiding them outright serves the same intent

Verified on the running VM (v5.0.0, shell restarted): all three off shows a bare
clock; toggling each on makes exactly its glyph appear in accent colour within
the poll interval, driven from the CLI the way the keybindings do. The click
path (`onClick` → same command, then an immediate refresh) is not exercised by
that test and still wants a real click. `noctalia plugins lint` passes on the
plugin. `[osd.kinds]` defaults `caffeine`, `dnd` and `nightlight` to
`true`, so a keyboard toggle also pops an OSD for free.

The original analysis follows, kept for the presentation idea (hover-reveal) and
the IPC facts.

#### Original analysis

Quattro puts a **single aggregate widget** `omarchy.indicators` in the bar centre
(`shell/plugins/bar/widgets/Indicators.qml`), which hosts six indicators from
`shell/plugins/bar/indicators/`:

| indicator | Monarch today |
|---|---|
| `Dnd.qml` | **missing** |
| `NightLight.qml` | **missing** |
| `StayAwake.qml` (caffeine) | **missing** |
| `Reminder.qml` | **missing** (relates to monarch-todo) |
| `ScreenRecording.qml` | have it, standalone |
| `Dictation.qml` | have it, standalone (voxtype) |

**The presentation is the real idea, not the list.** `Indicators.qml` splits its
children into an *active* block and an *inactive* block; the inactive block has
zero width until hovered, then reveals itself:

```qml
implicitWidth: root.revealInactiveIndicators
  ? inactiveHorizontalBlock.implicitWidth : 0
```

So an indicator that is *off* is still inspectable and clickable on hover, instead
of vanishing. Monarch's indicators today are binary: shown or gone. This is
strictly better and is what makes a six-indicator cluster tolerable in the bar.

Each indicator is tiny — the whole of `Dnd.qml` is a declarative block over a
shared `BarIndicator` base:

```qml
BarIndicator {
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false
  active: dnd
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Allow Notifications"
  inactiveTooltipText: "Silence Notifications"
  onPressed: function() { notificationService.setDoNotDisturb(!notificationService.doNotDisturb) }
}
```

**Feasibility on Noctalia v5: good.** Every state Monarch needs is already an IPC
verb, and each has both a getter and a toggle:

| indicator | read | write |
|---|---|---|
| DND | `notification-dnd-status` | `notification-dnd-toggle` |
| night light | *(none — see below)* | `nightlight-force-toggle` |
| caffeine | *(none — see below)* | `caffeine-toggle` |

**Known gap (still true, now moot for this item):** there is no
`nightlight-status` or `caffeine-status`. `msg status` returns only
`barVisible`, `panelOpen`, `activePanelId`, `locked`; the complete inventory of
read verbs in the binary is `bluetooth-status`, `wifi-status`,
`notification-dnd-status`, `color-scheme-get`, `theme-mode-get`, `wallpaper-get`,
`get-volume`, `log-level-status`, `workspace-alert-status`. So a *plugin* can
toggle nightlight and caffeine but cannot read them back. Two partial escape
hatches were found while checking:

- both have idempotent setters, not just toggles — `caffeine-on|off|enable|
  disable` and `nightlight-on|off|enable|disable`, plus `nightlight-force-toggle`
- `[nightlight] force` is a real config key — but **it is not a state readback**:
  toggling with `nightlight-force-toggle` in the VM left
  `~/.local/state/noctalia/settings.toml` without a `[nightlight]` section at
  all. Like caffeine (a live logind/wayland inhibitor), the forced state exists
  only in the running shell. Nothing on disk to poll for either one

Neither is needed now that the stock widgets do the job, but the two missing
getters are the right upstream request for anything plugin-side — they are the
*only* way to read these states from outside the shell.

~~**Plan:** one `monarch/indicators` widget per concern (the plugin already hosts
five), plus a decision on whether Noctalia's Luau `ui.*` tree can express the
hover-reveal grouping.~~ Superseded — the stock widgets cover it. The
always-visible-pills fallback is what shipped, and the hover-reveal grouping
remains a later refinement (and an upstream request, since only the shell can
implement it).

### 5. Network widget on par with Omarchy quattro — *expensive, scope carefully*

Where the whole v5 question started. Quattro's implementation:

- `shell/plugins/panels/network/` — `Panel.qml` is **72 KB**, `Model.js` 12.5 KB
- backed by `bin/omarchy-network-status`, which prints tab-separated fields and,
  with `--verbose`: `ssid`, `signal_dbm`, `freq` (band), `bitrate`, interface, IP,
  prefix, gateway, RX/TX byte counters from `/sys/class/net/*/statistics/`,
  ethernet speed + duplex, and **router and internet ping latency**
- separate sibling panels: `wifiqr` (share the network as a QR code — also
  `bin/omarchy-network-qr`), `speedtest`, `disk-speedtest`
- plus `bin/omarchy-network-band` (2.4/5 GHz), `omarchy-network-password`,
  `omarchy-dns`

Monarch today uses the stock v5 `network` widget with `show_label = false`.

**The blocker is not the data, it is the panel.** `wifi-status`, `wifi-toggle` and
`network-toggle` exist as IPC, so the *indicator* half is easy. But a Noctalia
plugin cannot render the shell's own network panel, so matching quattro means
rebuilding a network picker inside a Luau `ui.*` tree — against a 72 KB QML panel
written with a full widget toolkit. That is not a like-for-like effort.

**Recommendation: split it.**
1. *Cheap and valuable now* — keep the stock widget for picking, and add the
   diagnostics quattro has and Noctalia lacks (band, bitrate, dBm, gateway/internet
   latency) as a `monarch/indicators` entry with a small panel. A
   `monarch-network-status` script modelled on `omarchy-network-status` is
   straightforward and is the reusable half.
2. *Only if step 1 proves insufficient* — replace the picker. Cost this against
   contributing the missing fields upstream to Noctalia instead.

Note quattro's status script has **no VPN detection**; Monarch already exposes VPN
state through the LazyVPN widget, so that is one place Monarch is ahead.

### 6. Theme and background plugins like Omarchy quattro

The original motivation: "le theming est trop rigide, je peux rien customiser".
Quattro has **two separate git-clone-based systems**, and conflating them is easy:

**Themes** — `omarchy-theme-install <git-url>` clones to
`~/.config/omarchy/themes/<name>` (name derived from the repo, stripping the
`omarchy-` prefix and `-theme` suffix). A theme directory holds:

- `colors.toml` — the palette (generated from `alacritty.toml` when absent)
- `shell.toml` — shell-specific settings
- `backgrounds/` — the theme's wallpapers

`omarchy-theme-set` then rebuilds a staging dir, flips the
`~/.local/state/omarchy/current/{theme,background}` symlinks, notifies the running
shell immediately, and re-themes 13+ apps in parallel (alacritty, hyprctl, btop,
vscode/opencode, helix, foot, tmux, gnome, claude, browser, obsidian, keyboard).

**Plugins** — `omarchy-plugin-add <git-url>` clones to
`~/.config/omarchy/plugins/<id>`, validated by `omarchy-plugin-validate`. A
`manifest.json` declares `id`, `name`, `description`, `kinds`, `entryPoints`
(`barWidget` / `bar`), and optional `barWidget.defaultSection`. First-party
plugins live in `$OMARCHY_PATH/shell/plugins` and are prefixed `omarchy.`. The
catalog (`omarchy-plugin-catalog`) merges both trees and is the single source of
truth for bar widget selection. **Bar widgets and plugins are the same thing** —
which is why `omarchy bar put` can offer any installed plugin.

**How this maps onto Noctalia v5:**

| quattro | Noctalia v5 |
|---|---|
| user themes cloned from git | palettes in `~/.config/noctalia/palettes/`, no installer |
| `colors.toml` per theme | `Monarch.json` (v4 schema, unchanged) |
| per-app retint, 13 apps | template catalog, `templates-apply` |
| user-authored templates | **absent — v5 rejects `[templates.<name>]`** |
| `backgrounds/` inside the theme | `[wallpaper] directory`, one folder |
| plugin = bar widget, git-installable | Luau plugins, no installer or catalog |

**The sharpest regression is the loss of user templates.** v5 renders only
catalog ids; a template that is not in the builtin or community catalog cannot be
rendered at all. Monarch already pays this: sddm and herdr are rendered by
`monarch-theme-apply` off the `colors_changed` hook precisely because they have no
catalog entry. That escape hatch works but does not scale to user-authored
theming, which is what was asked for.

**Decide between, in increasing order of cost:**
1. keep extending the `colors_changed` hook — works today, no upstream dependency,
   but every new app is Monarch code rather than user data
2. ask upstream for a local template source (a directory of user templates
   alongside the builtin and community trees). This is the smallest change that
   actually restores what was lost
3. build a Monarch-side theme installer that git-clones into
   `palettes/` + a Monarch-owned backgrounds tree, and renders user templates from
   the hook. Restores quattro's *user* experience without upstream, at the cost of
   Monarch owning a renderer

**Note this subsumes blocking item 2.** Quattro resolves per-theme backgrounds by
searching two directories — `~/.local/state/omarchy/current/theme/backgrounds/`
*and* `~/.config/omarchy/backgrounds/$THEME_NAME/`, the latter being the user's own
additions for that theme — and cycles within them (`omarchy-theme-bg-next`).
Monarch's existing `~/.config/monarch/backgrounds/monarch/` already mirrors the
second path exactly. So rather than fighting for a Noctalia IPC that does not
exist, do the resolution Monarch-side in `monarch-theme-apply` and write the
result with `wallpaper-set`. Design items 2 and 6 together.

---

## v5 facts worth not rediscovering

Hard-won during the port; all verified against a running v5.0.0-beta.8.

**The validator has blind spots.** `noctalia config validate` does *not* check
inline tables, `[plugin_settings]` keys, widget ids, or enum values.
`noctalia config export merged` does not validate at all — it echoes back
whatever you wrote, including keys the shell rejects. Authoritative sources are
`noctalia msg --help`, the error strings in the binary, the settings UI as
rendered, and above all `/usr/share/noctalia/assets/translations/en.json`.

**The translations catalog is the setting index.** It is how `hide_when_no_media`,
`hide_when_empty`, `labels_only_when_occupied`, `glyph` and
`lockscreen.fingerprint` were all found. Search it *before* guessing a key name.

**The settings-UI grouping is not the TOML section.** The catalog path
`settings.schema.shell.telemetry` corresponds to the key `telemetry_enabled` under
`[shell]`; `shell.telemetry` is rejected as an unknown setting. Confirm the real
key against the binary, not the UI path.

**Per-widget settings are top-level `[widget.<id>]` sections.** Never inline
tables in a bar lane — the TOML validator accepts them and the widget is silently
dropped at load time. Bar lanes hold plain strings only.

**Bar lane arrays are replaced across `.toml` files, not merged.** A second file
declaring `end = [...]` wipes the whole lane rather than appending. This is why
install-time widget wiring is not viable: the user's lane would freeze at its
install-day value and stop tracking Monarch's defaults. Widgets that depend on an
optional package belong in the shipped layout, hiding themselves when the package
is absent.

**Plugin binaries need absolute paths.** Noctalia is started by the compositor,
so its PATH is only `/usr/local/sbin:/usr/local/bin:/usr/bin` — a bare command
name silently fails to launch. `indicator.bin()` resolves commands from the repo's
`bin/`; `indicator.pkgBin()` resolves package binaries under `/usr/bin`. Using the
wrong one leaves the widget permanently hidden with no error.

**Plugin API level is 22.** `require()` of a relative `.luau` module needs ≥22
(and the extension is mandatory). The build accepts 3–23 despite the docs
advertising 3–27, which rules out `runAsync`'s argument-array form (24+) — hence
the hand-quoting in `agents.luau`'s `shellQuote`. Entry ids are unique across the
whole plugin, not per kind. Settings must use `label_key` / `description_key`
with a `translations/` catalog; a literal `label` is rejected.

**An unparseable config falls back to defaults silently.** No notification, no
message on the bar — the shell simply comes up with stock settings. The tells
are visual (the Monarch palette reverts to Noctalia's) and, decisively,
`noctalia msg color-scheme-get` returning `builtin Noctalia` instead of
`custom Monarch`. `noctalia config export merged` is what prints the actual
parse error with a line number; `config validate` on a file that was truncated
mid-copy can still pass, so when testing in the VM, checksum the config after
copying it in rather than trusting the copy.

**`config-reload` applies config changes live** — verified by changing a clock
format and reading it back off the bar. A full shell restart is only needed when
the config file itself is replaced wholesale.

**v5 has no changelog or telemetry wizard.** Only the plain `[shell]
telemetry_enabled` opt-out. The v4 `shell-state.json` version floor is obsolete.

**v5 paints the wallpaper from `[wallpaper] directory` with no persisted state.**
Verified by cold-starting the shell after stripping every wallpaper entry: the
Monarch background still appeared on the first frame. The v4 cache seeding is
therefore unnecessary, not merely obsolete.

---

## Testing

Every feature is tested by building an ISO and booting it in QEMU
(`monarch-iso`), never by deploying into `~/.local/share/monarch` on the live
machine. `monarch-iso-make --local-source` mounts `$MONARCH_PATH` into Docker, so
no commit or push is needed to test a change.

Note the VM disk image lives on `/tmp`, which is a 16 GB tmpfs mounted with
`usrquota`. An 11 GB image leaves very little headroom, and exhausting the quota
makes unrelated commands fail with `EDQUOT` in confusing ways.
