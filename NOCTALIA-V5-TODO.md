# Noctalia v5 — migration TODO

State of the `noctalia-v5` branch and what is left on it.

Noctalia v5 is a native C++ Wayland shell: no Qt, no Quickshell. v4 is frozen, so
this migration is forced rather than opportunistic. The package is `extra/noctalia`
in the Arch official repos, so there is no packaging work — the binary is
`noctalia`, the daemon is `noctalia -d`, and IPC is `noctalia msg <verb>`.

Branch status: 20 commits, 86 files, +4706 / −3736 vs `dev`, pushed, and taking
merges through PRs rather than direct commits. Tests 58/58 (CLI) and 39/39
(menu), `bin/monarch commands --check` OK on 258 commands, `monarch-menu --check`
OK on 266 entries.

What is left is items 1, 2, 5 and 6 below. **Item 1 is now the one to write**: it
was deliberately deferred until the branch was feature-complete, and with the
menu finished (item 7) nothing else blocks it.

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

### 2. Per-scheme wallpaper directory pinning — *done, verified in a booted VM*

v4 repointed `wallpaper.directory` at the active scheme's background folder on
every color change (`monarch-theme-apply`). v5 exposes no IPC for it: there is
`wallpaper-set`, `wallpaper-get`, `wallpaper-next/previous/random`, but nothing
that moves the picker's source folder.

**Shipped solution — a symlink farm at a fixed directory.** Rather than move
`wallpaper.directory` per scheme (which would need the unverified two-`.toml`
merge-precedence trick and a `config-reload`-repoints-the-picker assumption),
`config.toml` pins it once at `~/.config/monarch/backgrounds/current`, a
Monarch-owned directory of symlinks that `monarch-theme-apply` rebuilds on every
`colors_changed` hook. The farm unions the active scheme's shipped
(`themes/<scheme>/`) and user (`~/.config/monarch/backgrounds/<scheme>/`)
backgrounds — the same two-folder model `omarchy-theme-bg-next` uses — with the
user file shadowing a shipped one of the same name. The directory path never
changes, so no reload is needed; the native picker and `wallpaper-next/-previous`
cycle whatever the farm currently holds. Rebuild only ever `unlink`s the links,
never their targets, so no wallpaper file is deleted.

**Cold start needs a first-run stamp.** An earlier note here claimed the
config-stage `monarch-theme-apply` was enough to paint the first frame. It is
not, and a booted VM showed the desktop coming up on Noctalia's own bundled
wallpaper. The config-stage run builds the farm but cannot apply anything —
noctalia is installed by then but is not *running*, so `apply_wallpaper` returns
early. Noctalia then starts and posts its own default, which is a real existing
file, so an "apply only when nothing is set" test reads it as a deliberate choice
and declines on every later hook and every later boot. `sync_wallpaper` therefore
records that a Monarch wallpaper actually reached the shell, in
`~/.local/state/monarch/wallpaper-applied`, and applies one while that stamp is
missing *or* while what is set no longer exists. The stamp is written only when
`wallpaper-set` succeeded, so the config-stage run does not claim a wallpaper it
never set.

**Custom folders.** The picker scans one directory flat, so the farm can only
hold file links, not a mounted subdirectory. A user who wants a whole collection
(e.g. `~/Pictures/Wallpapers`) in every scheme drops a directory symlink into
`~/.config/monarch/backgrounds/sources/`; `sync_wallpaper` flattens each mounted
folder's images into the farm — the "pass N directories" model
`omarchy-menu-images` uses, adapted to Noctalia's single-directory picker. The
farm's `find` filters by image extension (jpg/jpeg/png/gif/bmp/webp), matching
`omarchy-theme-bg-next`, so a stray `.txt`/`.md` in a mounted folder is ignored.
Union priority (first to claim a basename wins): per-scheme user → shipped →
mounted sources.

Files: `config/noctalia/config.toml` (`[wallpaper] directory`),
`bin/monarch-theme-apply` (`sync_wallpaper`), `install/config/config.sh` comment.
**Verified in a booted VM** (autoinstalled from the branch ISO): the union and
its priority, a directory symlink under `sources/` flattened in, the extension
filter, stale-link cleanup with the link targets untouched, and the farm
following a scheme change in both directions. Noctalia's own `wallpaper-set`
applies a farm *link* path and the screen changes, `wallpaper-next` cycles the
farm, and after a scheme change the same noctalia process cycles the new contents
with no restart — so the picker re-scans the directory live, as assumed.

Two things the VM corrected. The `colors_changed` hook fires ~5s after the
change, not synchronously, which reads as "the hook never fired" if you look too
early. And v5 passes the hook **no arguments** — v4's appearance as `$1` is gone,
so both the appearance and the scheme name come over IPC; the header comment
claiming otherwise was wrong and has been fixed.

**The picker itself is a separate layer (Part 2, tied to item 6).** The user
wants Omarchy quattro's image-grid switcher, which is a Quickshell plugin
(`omarchy-shell image-selector open` → its `ImagePicker`) and does not port.
Reproducing it on v5 means building an image-grid picker as a Noctalia `[[panel]]`
over the `ui.*` tree (`image`, `scroll`, `input`, `button`; keyboard via
`capture_keys` ≥ 13, in range) reading the same two folders and driving
`wallpaper-set` — the same rendering-layer effort as item 7's menu panel. The
farm above is the shared data model both the native picker and a future grid sit
on. Decide alongside items 6 and 7.

---

## Deferred by choice

### 3. Firefox / pywalfox template

Explicitly set aside. No v5 blocker known; it is simply not started.

---

## New features requested

Three net-new features modelled on Omarchy quattro (items 4–6), detailed below
against the actual `basecamp/omarchy@quattro` source. Item 7 was not requested:
it came out of a later review of quattro's menu and is recorded here because it
is the same kind of decision.

### The architectural catch, read this first

**Omarchy quattro's shell is QML/Quickshell. Noctalia v5 is native C++ with Luau
plugins.** Quattro dropped waybar and now ships its own shell under `shell/`
(`shell.qml`, `Commons/`, `Ui/`, `services/`, `plugins/`), configured by
`~/.config/omarchy/shell.json`.

So the two projects took opposite bets at the same moment: Omarchy moved *to*
Quickshell, Noctalia moved *away* from it. **No quattro source file can be
reused — every item below is a reimplementation** against Noctalia's Luau plugin
API, whose ceiling this build sets at API level 23 (no `runAsync` argument
arrays, declarative `ui.*` tree only).

Reimplementation is not the same as impossibility, and an earlier revision of
this file overstated the ceiling by treating "bar widgets" as the whole plugin
API. **A v5 plugin declares five kinds of entry** — `[[widget]]`, `[[panel]]`,
`[[launcher_provider]]`, `[[desktop_widget]]`, `[[shortcut]]` — so quattro's
*architecture* often does port even though its code does not. Item 7 is the case
where that distinction changes the answer outright.

The authoritative API reference is `noctalia.d.luau` at the root of
`github.com/noctalia-dev/official-plugins`: full type declarations for
`noctalia.*`, `barWidget.*`, `panel.*`, `launcher.*`, `desktopWidget.*`,
`shortcut.*` and the `ui.*` node set, plus the entry-point callback list. Read it
before concluding that something cannot be done; the two plugin repos
(`official-plugins`, `community-plugins`) are the worked examples.

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

### 7. Menu: quattro's data-driven menu, as a Noctalia panel

**Split in two. Step 1 is done; step 2 is the panel.**

- **Step 1 — the data model, rendered by fuzzel.** Shipped on `feat/menu-data`:
  `default/monarch/monarch-menu.jsonc` (266 entries), `bin/monarch-menu` reduced
  to a renderer, the user overlay moved from sourced bash to JSONC, and
  `test/monarch-menu-test.sh` covering loading, the overlay, routes, guards and
  navigation — the last through a fake `fuzzel` on `PATH`, so none of it needs a
  compositor. `monarch-menu --check` validates the data in CI.
- **Step 2 — the Noctalia panel.** Shipped on `feat/menu-panel`: the
  `monarch/menu` plugin renders the tree, and `bin/monarch-menu` drops the picker
  and the renderer to become the data server plus a `panel-toggle` route.
  Verified in the VM: routes, guards against real hardware, the fonts provider
  with the current value ticked and pre-selected, keyboard navigation, global
  search across the whole tree with breadcrumbs, and an action that actually
  flipped do-not-disturb. Quattro's `disabled` convention came with it: 55
  Install rows now dim and tick what is already installed, 28 Remove rows hide
  what is not there. A `[[launcher_provider]]` entry puts the whole menu behind
  `/mm` in Mod+Space. **fuzzel still ships** — `monarch-menu-select`, `-input`,
  `-file` and `-keybindings` all still use it.

  Not ported, deliberately: quattro's `apps` provider lists desktop entries
  inside the menu and offers right-click uninstall. Monarch's Apps row opens the
  Noctalia launcher instead, which already ranks and pins applications. The
  uninstall gesture is not recoverable on this API level anyway — `onRightClick`
  is accepted only by `ui.button`, never by a row, and `panel.openContextMenu`
  needs `plugin_api 28` against our ceiling of 23. Revisit if that ceiling
  moves.

**What quattro did.** `bin/omarchy-menu` went from ~800 lines of nested bash to
**52 lines** of IPC wrapper. The content became data
(`default/omarchy/omarchy-menu.jsonc`, 358 lines), the rendering became a shell
plugin (`shell/plugins/menu/Menu.qml`, 1473 lines), and the pure logic became
`MenuModel.js` (524 lines, loadable by Node so `test/shell.d/menu-test.sh` and
`menu-guards-test.sh` exercise it directly). Their data model:

- Object keys are ids; **dotted ids are the tree** (`trigger.share.file` is a
  child of `trigger.share`). No `parent` field to keep in sync.
- Kind is inferred: `action` → action, `target` → link, otherwise submenu.
- Fields: `icon`, `iconFont`, `label`, `title`, `aliases`, `description`,
  `provider`, and three shell-condition guards — `when` (hide), `checked`
  (append ✓), `disabled` (keep listed, dim, ✓, unselectable).
- The user's `~/.config/omarchy/extensions/omarchy-menu.jsonc` overlays the
  defaults **per key and per field**: reusing a shipped id retitles or re-icons
  a row without re-declaring its action, and keeps its position.
- `provider:` fills a submenu at runtime (`apps`, `fonts`, `power-profiles`),
  one tab-delimited `label\tvalue\tcurrent` line per row.
- Guards are batched into **one** bash process per (re)load and per open, off a
  single `pacman -Q` snapshot, with `$(...)` readers shared between rows
  (`GUARD_READERS`); a test fails the build when a multi-row reader is missing
  from that list.

**Why this ports, contrary to what this file said before.** The menu needs a
panel, and v5 plugins can declare one. Verified against `noctalia.d.luau` and
the two plugin repos:

| quattro | Noctalia v5 |
|---|---|
| Quickshell plugin `omarchy.menu` | a `[[panel]]` entry of a Monarch plugin |
| `Menu.qml` rendering | `panel.render(...)` over the `ui.*` tree |
| `omarchy-shell shell toggle omarchy.menu '{"menu":"style"}'` | `noctalia msg panel-toggle monarch/menu:menu style` — the panel's `context` **is** the route, delivered to `onOpen(context)` |
| ad-hoc plugin calls | `noctalia msg plugin <author/plugin:entry> <target> <event> [payload]` → `onIpc(event, payload)` |
| `MenuModel.js` | a Luau module behind `require("./model.luau")` |
| JSONC data + user overlay | same shape, read with `noctalia.readFileAsync` |
| `apps` / `fonts` providers | `runAsync`, `commandExists`, `processMatches`, same row contract |
| search inside the menu | `noctalia.fuzzyScore`, plus a `[[launcher_provider]]` entry with `include_in_global_search` |
| `omarchy-menu-select` / `-input` | `ui.input` in the panel, or the same launcher provider |

The `ui.*` set is large enough: `column`, `row`, `box`, `label`, `markdown`,
`glyph`, `image`, `separator`, `spacer`, `progress`, `button`, `graph`, `input`,
`select`, `slider`, `toggle`, `scroll`, `dragSource`, `dropZone`. Panel
callbacks are `onOpen(context)`, `onClose()`, `onKey(chord, pressed)`,
`onIpc(event, payload)`, `onFrameTick(deltaMs)`.

**The manifest gates are all below our ceiling.** `dismiss_on_outside_click`
needs API ≥ 8, `keyboard_focus` ≥ 10, `capture_keys` ≥ 13 — read off shipped
plugins that declare them (`bitwarden` 8, `tailscale` 10, `bookmarks` 13). This
build accepts up to 23, so a keyboard-driven menu panel is in range. Only
`panel.openContextMenu` (≥ 28) is out, and the menu does not need it.

**Two things this buys that fuzzel cannot.** The panel is drawn by Noctalia, so
it is themed with the rest of the shell for free; and a `[[launcher_provider]]`
entry makes every menu action reachable from the global launcher — something
even quattro does not do, since its search stops at the menu's own field.

**What it costs.** A comparable panel plugin — `dunarand/bookmarks`, a
searchable list with `capture_keys` — is 1447 lines of Luau, in the same range
as quattro's 1473 lines of QML. Budget a rendering layer, not a translation.
And note the guard problem comes back with it: today's bash builds only the
level being shown, lazily, so per-row conditions are cheap; a panel evaluates
the tree before drawing, which is exactly why quattro batches. `MenuModel.js`
stops being a QML curiosity and becomes the reference to port.

**Reference implementations to read first**: `noctalia/notes` (a `[[panel]]` +
`[[launcher_provider]]` + `[[widget]]` in one manifest, with
`width`/`height`/`placement`/`position`), `dunarand/bookmarks` (keyboard-driven
searchable list), `noctalia/kaomoji` (launcher provider with category filters).

**Only then can fuzzel leave `install/monarch-base.packages`.** It currently has
five consumers — `monarch-menu`, `monarch-menu-select`, `monarch-menu-input`,
`monarch-menu-file`, `monarch-menu-keybindings` — and one theming dependency:
`fuzzel` is in `community_ids` in `config/noctalia/config.toml`, so dropping the
package means dropping that template id too. Removing the package before all six
are handled breaks the menu outright.

**There is a cheaper intermediate step, and it does not need the panel.**
`noctalia dmenu [-p prompt]` reads newline-separated items on stdin, presents
them in the launcher and prints the selection on stdout — the same contract as
`fuzzel --dmenu`, already flagged as "not yet adopted" in `AGENTS.md`. It is
absent from `noctalia --help` but present in the shipped binary (v5.0.0). Left
to verify before swapping: whether it accepts empty stdin and returns typed text
(what `monarch-menu-input` needs), and what replaces `--lines` / `--width` /
`--select`, which it does not take. If it holds up, fuzzel can be dropped in a
first pass, and the panel port then becomes purely about the menu's *shape*
rather than its renderer.

#### Menu: fixes already landed

Independent of the port, applied to the current bash menu:

- `monarch menu screenshot` routed to `show_screenshot_menu`, which was never
  defined — a dead route that failed silently. Now runs
  `monarch-capture-screenshot`, matching quattro's `trigger.capture.screenshot`.
- `toggle_existing_menu` ran `pkill -x fuzzel` and stopped there, leaving the
  monarch-menu behind the picker alive: an empty selection reads as "go back",
  so the keybind popped the parent menu back up instead of closing the menu. It
  now tracks its own pids in `$XDG_RUNTIME_DIR/monarch/menu{,-picker}.pid`
  (re-checked against `/proc`, since a pid file outlives its process) and kills
  both. **A foreign picker is still dismissed**, and has to be: fuzzel is
  single-instance per display — it holds
  `/run/user/UID/fuzzel-$WAYLAND_DISPLAY.lock` and a second instance exits 1
  with `failed to acquire lock`. So "leave other pickers alone" is not an
  option; the menu simply would not open. Verified in the VM.
- `install "obs-studio" "pinta" "kdenlive"` installed only `pinta`: `install()`
  reads `$1` as the label and `$2` as the package list, and ignored `$3`.
- Cosmetic: `show_setup_security_menu` and `show_setup_default_menu` were
  indented as if nested. They were not — a mis-indentation that made
  `show_setup_default_menu` read as a function defined inside another one.

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

**A plugin is not just bar widgets.** The five entry kinds are `[[widget]]`,
`[[panel]]`, `[[launcher_provider]]`, `[[desktop_widget]]` and `[[shortcut]]`,
and one manifest may declare several. Bar widgets are simply the only kind
Monarch uses so far — do not read that as the API's ceiling, which is how item 7
was nearly written off. `noctalia.d.luau`, at the root of
`github.com/noctalia-dev/official-plugins`, is the authoritative surface: it
declares `noctalia.*`, `barWidget.*`, `panel.*`, `launcher.*`, `desktopWidget.*`,
`shortcut.*`, every `ui.*` node and every entry-point callback. Consult it before
the binary's strings.

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
