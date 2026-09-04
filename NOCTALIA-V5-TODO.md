# Noctalia v5 — follow-up roadmap

The migration from Noctalia v4 is feature-complete. This uncommitted working
document tracks only follow-up work. Do not start an item without explicit user
validation. Update its status after every test, PR and merge.

Statuses: `candidate`, `approved`, `in progress`, `in review`, `merged`,
`deferred`, `rejected`.

## Installation architecture handoff — 2026-08-27

- **Status:** in review
- **Scope:** package Monarch as a system runtime, split runtime/defaults into
  two packages, and make the ISO use the phased installer plus the same
  first-boot provisioning interfaces.
- **Product decision:** Pangolin/Newt is deferred and is not part of these PRs.
- **Compatibility decision:** there is no installed fleet to migrate yet. The
  legacy installer tree and historical migrations were removed intentionally;
  migration compatibility will be reviewed separately if it becomes relevant.

Open PRs:

- [`monarch#170`](https://github.com/monarch-os/monarch/pull/170),
  `noctalia-v5` → `dev`: Noctalia V5 plus the packaged Monarch runtime.
  Main feature commit: `a16e873c`; latest branch commit after merging current
  `dev` and cleaning fixtures: `85f0b31c`.
- [`monarch-pkgs#64`](https://github.com/monarch-os/monarch-pkgs/pull/64),
  `monarch/runtime-packages` → `main`: `monarch` and `monarch-settings`, with
  the obsolete standalone `monarch-dns` package removed. Commit: `8c97c9b`.
- [`monarch-iso#19`](https://github.com/monarch-os/monarch-iso/pull/19),
  `noctalia-v5` → `main`: packaged local-source builds, phased orchestrator,
  dashboard, full-disk/free-space installation, deferred provisioning,
  factory reset, Tailscale, diagnostics and release sidecars. Commit:
  `de7414e`.

The `monarch` and `monarch-iso` integration branches are deliberately both
named `noctalia-v5`. An older remote ISO branch named
`monarch/installer-orchestrator` points at the same implementation but has no
PR and can be deleted after merge.

Validation completed before opening the PRs:

- a complete local-source ISO build succeeded;
- interactive ISO boot, installation, reboot and desktop startup succeeded in
  QEMU;
- unattended and deferred-owner installation paths were exercised in QEMU;
- `monarch-iso/test/all` passed: every shell unit suite and 68 Python tests;
- Monarch CLI, menu, network, display, power, kernel-header and packaged-runtime
  shell suites passed;
- the Niri socket-discovery test passed outside the restricted agent sandbox;
- repository and PyPI resolution passed for all 220 package names;
- PKGBUILD/install-hook syntax and all three repository diffs passed their
  static checks.

Remaining before merge/release:

1. wait for and review all GitHub CI results;
2. merge/publish the runtime and settings packages before relying on a normal
   non-local ISO build, then merge the ISO PR;
3. rebuild once from published packages rather than `--local-source`;
4. retain the planned real-hardware UEFI/LUKS validation for free-space install
   and factory reset before a release claim;
5. decide separately whether the local changes in this roadmap belong in a
   documentation commit; they are intentionally outside PR #170 today.

## Completed

- Existing installations migrate from `noctalia-shell` to native Noctalia v5.
- Wallpapers follow the active palette through Monarch's symlink farm; the
  native wallpaper picker remains the source of truth.
- Status, privacy, display, network and coding-agent widgets are native Luau
  plugins.
- The network panel covers Wi-Fi, DNS and diagnostics; network and disk speed
  tests are exposed under Trigger.
- The data-driven Monarch menu, global search and compact input/select panels
  replace the old nested picker.
- `monarch-about` has responsive layouts plus image, text and reset branding.
- Removed preinstalled packages, webapps and TUIs can be restored safely;
  failures preserve their retry state.
- Crash capture keeps diagnostics local and exposes its state in the menu.
- Noctalia's first-run setup panel is skipped on fresh Monarch sessions.
- SDDM and application templates follow the active palette; new Obsidian vaults
  are themed automatically.
- Hardware guards, SSH setup, plugin settings, software organization, default
  coding agents and Signal match the accepted Quattro scope.

## Quattro parity snapshot — 2026-08-27

The primary desktop migration is feature-complete, but Monarch does not yet
match every part of Quattro's product experience. This is the historical
snapshot against Quattro `946704f3`; Q21 below supersedes it with a release-by-
release audit through v4.0.2 and current Quattro head.

Highest-value gaps still worth evaluating:

- harden FIDO2 credential staging and the privileged DNS helper;
- repair first-run notification actions and keep command arguments structured;
- protect the supported update path with a lock, preflight checks and Quattro's
  ALPM pre-transaction guard;
- install, update and remove code-free Monarch theme bundles;
- let users author application templates missing from Noctalia's catalogues;
- add Quattro's crash-notification mute flow to the local crash diagnosis;
- evaluate the restrained About-logo sheen without reopening the logo design.

Known gaps that are currently accepted, deferred or rejected:

- Noctalia has no atomic editable-plugin clone and built-in fallback lifecycle;
- clock-format cycling, direct timezone access, a dedicated microphone widget,
  weather and active-window widgets are not part of the default bar;
- Dropbox integration is deferred, ONCE is rejected in its current form, and
  Sunshine remains an independent future integration;
- Monarch deliberately keeps Noctalia's native audio, wallpaper and plugin
  management surfaces instead of rebuilding Quattro's QML panels;
- a full Quattro-style user-authored shell and bar-plugin architecture remains
  out of scope for the Noctalia v5 migration.

Already covered by Monarch or a richer Noctalia equivalent: Tailscale and
Taildrop, Ori and Antigravity, Signal, opt-in sudoless Docker, the FIDO2 product
flow apart from Q12's hardening, compact and repositionable bars, Quattro
palettes, background selection/import, and the network, display and coding-
agent panels. Q21 corrects the earlier assumption that Dell XPS speaker tuning
was complete.

## Active roadmap

### Q1 — Bar position

- **Status:** merged — PR #161; single-monitor VM validation complete
- **Scope:** expose Top, Bottom, Left and Right under `Style > Menu Bar`, persist
  the choice safely and retain the visibility toggle.
- **Acceptance criteria:**
  - the current position is checked in the menu;
  - changing it applies without logout and survives reboot;
  - unrelated user configuration is preserved;
  - every stock and Monarch widget renders in all four orientations;
  - panels anchor to the correct edge;
  - reserved space, auto-hide and multi-monitor behaviour remain correct;
  - menu, CLI and config validation pass;
  - all four positions are visually verified in the VM.

Noctalia accepts `position` in bar config but exposes no position IPC. Use a
safe config writer followed by `config-reload`. Evaluate drag-to-edge separately.
The vertical layouts currently stack the clock text one character per line;
track that visual correction under Q2 rather than expanding Q1.

### Q2 — Compact Monarch bar design

- **Status:** merged — PR #162; four-position VM validation complete
- **Depends on:** Q1 configuration inventory and visual approval.
- **Scope:** make the bar thinner and tighter, with a rectangular active
  workspace indicator.
- **Acceptance criteria:**
  - compare at least two native-setting prototypes in the VM;
  - remain readable at 1x and scaled displays;
  - keep spacing consistent across start, centre and end;
  - keep occupied, empty and focused workspaces distinguishable;
  - preserve mouse and keyboard workspace switching;
  - avoid clipping in horizontal and vertical layouts;
  - replace the native widget only if its schema cannot express the design.

Quattro uses a 26 px horizontal and 28 px vertical bar with compact fixed-width
workspace slots. Port the visual goal through Noctalia, not Quattro's QML.

### Q3 — Plugin menu integration audit

- **Status:** completed — native-only integration approved; no implementation needed
- **Scope:** decide whether `Setup > Plugins` needs direct actions alongside
  Noctalia's native settings.
- **Acceptance criteria:**
  - exercise discovery, install, update, enable, disable, removal and placement;
  - record warnings for unsandboxed plugin code;
  - document missing or awkward flows with reproductions;
  - do not duplicate native flows that work;
  - evaluate editable cloning separately for reload, id collision, routing and
    recovery to the built-in plugin;
  - obtain approval of the audit conclusion before implementation.

Quattro exposes Enable, Disable, Add, Clone and Remove. Its clone operation also
keeps placement/settings and redirects the built-in id. Do not promise that
unless Noctalia supports it safely.

Audit findings on Noctalia 5.0.0:

- the native page covers catalog discovery, Git/path sources, enable/disable,
  source updates, auto-update scope, plugin settings and confirmed removal;
- adding a plugin materializes and enables it, but bar widgets still need a
  separate placement under `Bar: default`;
- panel placement is exposed in the plugin's generated settings;
- disabled plugins retain their files and settings; removal is available for
  catalog plugins, while local/path plugins are removed through their source;
- lower sources deterministically override duplicate ids, so a path source can
  stand in for an editable clone while preserving id-based settings and bar
  references;
- removing that overriding source disables the shared id, so the built-in
  fallback must be re-enabled manually;
- there is no one-click editable clone or source editor handoff comparable to
  Quattro;
- the store shows source and compatibility information but no trust warning,
  despite plugins being able to run commands and access arbitrary user paths.

Recommendation: retain the single native `Setup > Plugins` action. Do not add
duplicate enable, disable, update or remove pickers, and do not port Clone until
Noctalia provides an atomic override/fallback lifecycle. Track the missing trust
warning and post-install widget-placement handoff upstream rather than building
a parallel Monarch plugin manager.

### Q4a — Native theme and wallpaper selection audit

- **Status:** merged — PR #163; visual selector and VM validation complete
- **Scope:** determine whether Monarch needs its own theme picker or can expose
  Noctalia's native wallpaper panel as the unified theme workflow.

Audit findings on Noctalia 5.0.0:

- Appearance provides palette swatches and search, but separates palette and
  wallpaper configuration;
- the wallpaper panel already combines palette source, palette selection,
  dark/light/auto mode, wallpaper thumbnails, search, sorting and favorites;
- selecting a Monarch custom palette triggers templates and
  `monarch-theme-apply`; VM round-trips between Lumon and Monarch correctly
  changed the palette, wallpaper collection and selected wallpaper;
- the menu labels this capable panel only as `Background`, so theme selection
  is effectively undiscoverable;
- built-in palettes without a matching Monarch background directory clear the
  symlink farm and leave the previous wallpaper displayed from an empty picker;
- built-in palettes have no JSON file under `~/.config/noctalia/palettes`, so
  Monarch's SDDM, browser and keyboard residual theming cannot derive their
  colors even though Noctalia and its application templates can.

Conclusion: the native wallpaper panel remains the right low-level wallpaper
picker, but is not sufficient as Monarch's canonical theme selector. Palette
source terminology is implementation-facing, themes have no visual preview,
the wallpaper grid does not reliably refresh after a palette change, and the
flow gives no visibility into SDDM or Plymouth. Prototype a Monarch theme
selector that presents one theme catalogue and delegates the actual palette and
wallpaper mutations to Noctalia. It must also show whether SDDM follows the
selection and keep Plymouth explicitly manual because applying it rebuilds the
initramfs.

### Q4 — Import and manage backgrounds in the active scheme

- **Status:** merged — PRs #164 and #166; local and VM validation complete
- **Scope:** add a selected image to the active scheme's user collection and
  refresh the native picker.
- **Acceptance criteria:**
  - validate supported formats before mutation;
  - cancellation and invalid input change nothing;
  - naming collisions follow a non-destructive policy;
  - the image appears immediately in the picker;
  - it remains associated after scheme switches and reboot;
  - shipped backgrounds are never modified;
  - imported backgrounds can be moved to trash after confirmation;
  - shipped and external backgrounds remain protected from removal.

### Q5 — Installable Monarch theme bundles

- **Status:** merged ([#184](https://github.com/monarch-os/monarch/pull/184));
  physical-machine install validated with
  [`y0no/monarch-theme-q5-test`](https://github.com/y0no/monarch-theme-q5-test)
- **Depends on:** Q4 and an approved bundle format.
- **Scope:** define a code-free palette/background/metadata bundle with safe
  install, update and removal.
- **Acceptance criteria:**
  - bundles cannot execute hooks or arbitrary code;
  - validate accepted Git transports and repository layout;
  - record provenance and installed revision;
  - show update changes and preserve local backgrounds;
  - roll back failed install/update;
  - removal cannot delete unrelated files and handles the active theme safely;
  - palette, picker, app templates and SDDM remain synchronized;
  - cover local, remote and malformed bundles automatically.

Do not build an Aether-like GUI until the format and lifecycle are stable.

Q5 defines a declarative schema-1 bundle containing one Noctalia palette,
flat wallpaper assets, an optional preview and metadata. Installation accepts
only constrained HTTPS/SSH Git transports, rejects executable files, symbolic
links and unsupported repository content, records provenance, and publishes
the palette through a bundle-owned symlink. Updates stage and validate a fresh
clone before replacing the installed bundle, while removal refuses the active
theme and preserves user-imported backgrounds. Menu-driven install, update and
removal report their progress; interactive removal requires confirmation.

### Q6 — User-authored application templates

- **Status:** merged — PR #186.
- **Depends on:** native Noctalia user templates and Q5's format.
- **Scope:** restore local templates for apps absent from Noctalia's catalogues.
- **Acceptance criteria:**
  - use native Noctalia support rather than a Monarch renderer;
  - users can add a target and override a shipped one;
  - rendering failures name the template and preserve usable config;
  - templates apply on colour changes without restarting the desktop;
  - document the boundary between visual data and executable code.

Noctalia now accepts `[theme.templates.user.<id>]` in user TOML overlays and
reapplies them on palette or configuration changes. Monarch ships an inert,
data-only example and documents that replacing a catalogue template requires
removing its id from the corresponding enabled array. Hooks and dynamic output
commands remain trusted local code and are forbidden in Q5 bundles. Noctalia
preserves the previous output on template-evaluation errors, but direct writes,
multiple outputs and hooks are not transactional; stronger guarantees belong
upstream rather than in a duplicate Monarch renderer.

### Q7 — About refinement

- **Status:** candidate
- **Depends on:** explicit visual approval; keep the current logo unchanged.
- **Scope:** evaluate a restrained ASCII sheen and optional Set From Text action.
- **Acceptance criteria:**
  - static rendering remains the fallback;
  - custom text, images, wide Unicode and custom fastfetch configs do not
    corrupt the terminal or trigger resize loops;
  - animation stops with the window and has negligible idle CPU use;
  - responsive sizing remains correct;
  - visual evidence is approved before retaining the implementation.

Image, text and reset branding already exist. The only current Quattro gap is
the recent animated sheen and its safe fallbacks; do not reopen logo design.

### Q8 — Secondary widget interactions audit

- **Status:** merged — PR #167; source audit and VM validation complete
- **Scope:** compare left, right, middle and scroll actions with Quattro.
- **Acceptance criteria:**
  - record an interaction matrix for every default widget;
  - do not duplicate existing Monarch or Noctalia actions;
  - proposed actions have visible feedback and no binding conflicts;
  - test every retained interaction from the VM bar.

Audit findings against Quattro `0ae16948` and Noctalia v5 main:

- Noctalia already matches Quattro for volume (panel, mute and scroll),
  Bluetooth (panel and radio toggle), workspaces (click and scroll), brightness,
  tray items and the primary battery action;
- Monarch's network, display, agents and state indicators already preserve their
  useful custom actions; changing them would either remove a richer panel or
  duplicate a menu action;
- Quattro right-clicks its power widget to toggle the battery percentage.
  Monarch has the same toggle command but exposes it only through the menu;
- Quattro gives clock right-click to format cycling and middle-click to the
  timezone picker. Noctalia reserves middle-click consistently for widget
  settings, and Monarch has no persisted clock-format cycling command;
- Quattro maps media left/middle/right to play-pause/next/panel. Noctalia uses
  left for its richer media panel, right for play-pause, scroll for tracks and
  middle for widget settings. Rebinding it would trade away native conventions
  without adding capability;
- Quattro ships a dedicated microphone widget. Noctalia can express the same
  controls with a second `volume` widget targeting input, but Monarch's privacy
  widget already signals active capture. The dedicated widget was rejected as
  redundant after review;
- weather and active-window gestures do not apply because neither widget is in
  Monarch's default bar.

Recommendation: add only battery right-click →
`monarch-toggle-battery-percentage`. Keep Noctalia's native clock and media
gestures. Evaluate the input-volume widget separately with a visual prototype
before changing the default bar.

### Q9 — Optional service panels

- **Status:** completed — Tailscale/Taildrop shipped in PR #168; Dropbox
  deferred; custom audio rejected after audit
- **Scope:** evaluate Tailscale/Taildrop first; consider Dropbox and custom audio
  independently.
- **Acceptance criteria:**
  - audit native and existing Monarch capability first;
  - optional widgets hide cleanly when their package is absent;
  - install/remove leaves no broken bar entry;
  - account, privilege and network side effects are explicit;
  - approve and ship each service independently.

Tailscale audit findings:

- Monarch already installs the package, enables `tailscaled`, runs `tailscale up
  --accept-routes`, installs the admin webapp, and provides a symmetric removal
  path;
- unlike Quattro, the installer does not set the current user as Tailscale's
  operator, install a Taildrop receiver, expose Taildrop send/receive commands,
  or add a bar panel;
- Quattro's receiver is a persistent user service. It receives into a private
  staging directory, resolves collisions without overwriting, moves completed
  files into Downloads, and posts persistent clickable notifications;
- Quattro's send command uses Monarch-compatible primitives: the native file
  selector, `tailscale file cp`, and success/failure notifications;
- Quattro's bar panel adds connection state, up/down, account switching, exit
  nodes, peer browsing, copy actions and Taildrop send. Its QML implementation
  cannot be reused by Noctalia v5;
- Noctalia's community catalogue already offers `davemhammer/tailscale` and
  `rylos/tailnet`. Both provide native Luau panels, status, peer browsing,
  up/down and exit-node controls. Tailnet also receives Taildrop files; neither
  currently combines Quattro's Taildrop send and multi-account switching;
- automatically installing a community plugin would trust unsandboxed code and
  couple Monarch's service lifecycle to a separately versioned source. Shipping
  a third first-party panel would duplicate most of two maintained plugins.

Recommendation:

1. port Quattro's system integration only: operator permission, robust
   background receiver, `monarch tailscale send/receive`, install/remove
   lifecycle and tests;
2. keep the bar optional and direct users to Noctalia's plugin catalogue rather
   than automatically installing third-party code;
3. do not port account switching or a Monarch panel unless real use shows the
   community plugins insufficient;
4. audit Dropbox separately after Tailscale is resolved.

Installing Tailscale changes routing (`--accept-routes`), enables a privileged
system daemon, grants the user operator control over it, and enables a persistent
per-user receiver. The implementation must stop on package/daemon setup failure
and remove only Monarch-owned integration while leaving received files intact.

Dropbox audit findings:

- Monarch currently exposes neither Dropbox installation nor removal;
- Quattro installs `dropbox`, `dropbox-cli`, `libappindicator-gtk3`,
  `python-gpgme` and `nautilus-dropbox`, starts the client, and adds a dedicated
  bar panel;
- Noctalia has no Dropbox plugin in either its official or community catalogue;
- Dropbox's Linux client already publishes a tray item with login, sync state,
  activity, storage, preferences and folder access. Noctalia's native tray is
  therefore the supported low-maintenance UI;
- Quattro's panel adds pause/resume, login, recent local files and estimated
  storage usage. Its helper recursively stats the complete Dropbox tree every
  60 seconds and compares local bytes with a hard-coded plan quota. This can be
  expensive and misleading with large trees, selective sync, business plans or
  future quota changes;
- the Quattro plugin is QML and cannot be reused by Noctalia v5. Rebuilding it
  in Luau would duplicate the official tray while preserving the unreliable
  local quota approximation;
- Dropbox is proprietary, Linux support officially targets Ubuntu and Fedora,
  does not support Linux ARM, and may synchronize a substantial local dataset.
  Authentication opens a browser after the daemon starts;
- removal must stop the daemon and remove packages/integration while preserving
  `~/Dropbox`, account state and all synchronized user data.

Decision: defer Dropbox. The native tray would cover most useful interactions,
while the proprietary client has limited official Linux support and a dedicated
Monarch panel would add disproportionate maintenance for an optional service.

Custom audio audit findings:

- Quattro's panel provides output and input volume/mute, output and input device
  selection, a microphone level meter, and per-application playback volume;
- Noctalia v5 already provides output and input volume/mute, both device
  selectors and the per-application mixer in its native control-center audio
  tab;
- Noctalia additionally resolves application identities and icons, can pin each
  application stream to a specific output, and exposes input/output EasyEffects
  profiles when available;
- its bar volume widget already opens that panel, right-clicks to mute and
  scrolls to adjust volume. A second input-targeted widget is available but was
  previously rejected as redundant with Monarch's privacy indicator;
- Quattro's QML contains substantial snapshot, polling and device-workaround
  logic needed by Quickshell's PipeWire model. Noctalia implements the same
  lifecycle natively in its PipeWire service and C++ audio tab.

Decision: reject a Monarch audio plugin. Keep Noctalia's native panel as the
single audio surface; it is both more capable and cheaper to maintain. Q9 is
complete.

### Q10 — ONCE self-hosting

- **Status:** deferred — not a good fit in its current form.
- **Decision:** do not add ONCE to Monarch's menu. Its built-in catalog is
  compiled into the binary, while custom images must satisfy a narrow
  single-container contract (HTTP on port 80, `/up`, persistent `/storage`).
  Supporting tools such as Artemis would therefore require either a maintained
  ONCE fork or Monarch-specific adapter images, with little benefit over a
  dedicated Docker Compose installer.
- **Reconsider when upstream provides:**
  - an external configurable application catalog;
  - manifest or Docker Compose support;
  - explicit port and firewall handling;
  - enough relevant applications that work without Monarch-maintained adapters.

### Q11 — Guard direct Pacman system upgrades

- **Status:** merged — PR #174; runtime hook packaged in monarch-pkgs PR #66
- **Scope:** port Quattro's ALPM pre-transaction guard so full system upgrades
  normally run through `monarch update` rather than direct `pacman -Syu`.
- **Acceptance criteria:**
  - block short and long forms that combine sync with system upgrade;
  - leave package installs, removals and other non-system-upgrade transactions
    untouched;
  - let every Monarch-owned upgrade, channel and package-repair path opt in with
    one internal environment marker;
  - retain an explicit, documented escape hatch for intentional direct upgrades;
  - explain which Monarch update guarantees would otherwise be bypassed;
  - install the hook through the packaged runtime and cover it with shell tests;
  - audit every existing `pacman` invocation before enabling the hook.

Quattro installs `00-omarchy-update-guard.hook` as an ALPM `PreTransaction`
hook for package upgrades. Its helper inspects Pacman's parent command line and
aborts only sync-plus-sysupgrade transactions unless the official update path
sets `OMARCHY_UPDATE_PACMAN=1`; users can deliberately bypass it with
`OMARCHY_ALLOW_DIRECT_PACMAN=1`. The Monarch port should use equivalent
`MONARCH_*` markers and account for the packaged-runtime layout introduced by
the installation architecture handoff.

### Q12 — Security hardening parity

- **Status:** completed — FIDO2 atomic staging/removal safety and privileged DNS
  path pinning implemented with focused shell coverage
- **Scope:** port Quattro's FIDO2 staging and privileged DNS `PATH` hardening.
- **Acceptance criteria:**
  - reject a symlink or non-directory at `/etc/fido2` and a symlink or
    non-regular registration file;
  - create the FIDO2 staging file as root beside the final authfile, validate
    the generated path and type, publish it atomically and clean it on failure;
  - never stage authentication material at a predictable caller-owned path such
    as `/tmp/fido2`;
  - make FIDO2 removal reject unsafe path types and remove only the expected
    registration hierarchy;
  - pin `PATH` to trusted system directories whenever `monarch-dns` runs as
    root, while preserving unprivileged discovery of `sudo` and `pkexec`;
  - cover the symlink, replacement, cleanup and untrusted-`PATH` cases with
    focused shell tests.

Monarch currently writes `pamu2fcfg` output to predictable `/tmp/fido2` before
moving it as root. Quattro instead creates a root-owned unique sibling of
`/etc/fido2/fido2`, validates every privileged pathname and atomically renames
the completed file. Monarch's passwordless DNS helper also resolves bare system
commands without first discarding a potentially user-writable development
`PATH`; Quattro pins the path only after elevation.

### Q13 — Structured notification actions

- **Status:** completed — unified argv-safe notification actions implemented;
  first-run invitations and clickable file/capture notifications migrated
- **Scope:** repair the first-run notification invitations and converge every
  clickable Monarch notification on one argv-safe interface.
- **Acceptance criteria:**
  - define one unambiguous CLI contract for glyph, text, notification options,
    action label and command arguments;
  - preserve ordinary `notify-send` option parity where the generic helper
    continues to accept it;
  - never reinterpret notification text or a relayed command as shell source;
  - keep action arguments distinct through delivery and execution;
  - retain compatibility only where it can fail closed;
  - migrate every `--exec` caller and prove first-run Wi-Fi, update,
    fingerprint and agent invitations execute the intended argv;
  - verify Taildrop, Voxtype, screenshot and screen-recording actions against
    the same safety rules.

The current first-run callers pass option-first invocations and `--exec` to
`monarch-notification-send`, whose actual contract expects the glyph first and
does not implement `--exec`. Monarch already has the safer
`monarch-notification-action`; the audit must decide whether to make it the only
clickable path or replace both helpers with Quattro's direct D-Bus model.

### Q14 — Transactional update guardrails

- **Status:** merged — PR #175
- **Depends on:** Q11, which must share the same definition of an official
  Monarch update transaction.
- **Scope:** prevent overlapping updates and fail early when the machine cannot
  safely complete one.
- **Acceptance criteria:**
  - serialize `monarch update` with a per-user runtime lock and explain a
    concurrent refusal;
  - prove child processes and sleep inhibitors cannot accidentally retain the
    lock after the update exits;
  - check required free space before mutation and report an actionable failure;
  - prune the package cache before taking the snapshot so reclaimed space is
    not retained by that snapshot;
  - preserve interactive and unattended `-y` behavior;
  - always release the inhibitor and temporary state on success, failure and
    interruption;
  - test ordering around cache pruning, snapshot creation, package upgrade,
    migrations and post-update hooks.

Quattro implements these as `omarchy-update-lock`,
`omarchy-update-requires-free-space`, `omarchy-update-pkg-prune` and a dedicated
stay-awake lifecycle. Monarch currently inhibits idle inside
`monarch-update-perform`, but has no concurrent-update lock or disk-space
preflight and takes its snapshot before reclaiming package-cache space.

### Q15 — Small Quattro UX parity

- **Status:** merged ([#176](https://github.com/monarch-os/monarch/pull/176))
- **Scope:** resolve the remaining small interaction and default-tool gaps
  without overriding better native Noctalia behavior.
- **Acceptance criteria:**
  - add `Mod+Q` as an alternative close-window chord and present alternative
    chords coherently wherever Monarch lists keybindings;
  - do not add `hey-cli` or other Basecamp products to Monarch;
  - determine whether Noctalia's native clock supports live-second formats and
    efficient second-only refresh, then expose the formats only if both hold;
  - determine Noctalia's actual clipboard history cap before changing anything,
    and match Quattro's 500 entries only when the native setting supports it;
  - verify Niri internal-display recovery with automatic fractional scaling;
    record the Hyprland-specific clamshell fix as not applicable if Niri already
    preserves the resolved scale;
  - keep a source-backed accepted/rejected decision for every audited item.

Quattro's corresponding changes are a second close-window chord, lazy
`hey-cli`, two clock formats with live seconds, a 500-entry clipboard history
and a clamshell recovery fix for Hyprland's automatic scale. The latter three
must be tested against native Noctalia and Niri rather than ported mechanically.

Decisions accepted for Q15:

- ship `Mod+Q` beside `Mod+Shift+Q`, grouping alternative chords into one row
  in Monarch's keybinding picker;
- set Noctalia's native `clipboard_history_max_entries` to 500; its supported
  range is 10–10,000 (`noctalia-dev/noctalia@74e6c279`, `example.toml` and
  `src/config/config_limits.h`);
- reject `hey-cli`; Monarch must not integrate Basecamp products;
- reject live-second presets for now: Noctalia accepts `%S`, but
  `Bar::onSecondTick()` refreshes every bar surface each second regardless of
  the clock format (`src/shell/bar/bar.cpp` at `74e6c279`), unlike Quattro's
  conditional minute/second precision;
- record the clamshell scale fix as not applicable: Monarch's Niri helper only
  enables the internal output and never substitutes a numeric scale for an
  automatic one.

### Q16 — Per-program crash notification mute

- **Status:** merged ([#177](https://github.com/monarch-os/monarch/pull/177))
- **Depends on:** the existing local crash-capture and diagnosis flow.
- **Scope:** let a crash diagnosis mute or unmute repeat notifications for the
  affected program without disabling crash capture globally.
- **Acceptance criteria:**
  - derive one stable program identifier from validated crash metadata;
  - expose explicit mute, unmute and status operations;
  - suppress only desktop notifications, while retaining local crash records
    and diagnosis data;
  - make the muted state visible and reversible from the diagnosis instructions;
  - reject empty, malformed and option-like identifiers;
  - keep state per user and survive reboot without granting additional
    privileges;
  - prove one muted program does not silence another program or the global
    crash-capture controls.

Quattro's new `omarchy-crash-mute` keeps the crash watcher active but lets the
diagnosis skill silence one repeatedly crashing program. Monarch now provides
the same per-program distinction with stricter identifier validation, explicit
status control and tests proving that capture and other programs remain active.

### Q17 — Niri webcam recording overlay parity

- **Status:** merged ([#178](https://github.com/monarch-os/monarch/pull/178)); hardware-GPU smoke test pending
- **Scope:** restore the webcam-overlay quality lost when screen recording was
  ported from Hyprland to Niri.
- **Acceptance criteria:**
  - give the overlay a dedicated app-id and Niri rule so it opens floating,
    fully opaque, unfocused and outside the scrolling layout;
  - anchor it inside the selected monitor or recording region rather than the
    desktop globally;
  - restore small, medium and large presets with sizing relative to the capture
    area, including a useful default and runtime resizing where Niri permits;
  - wait for the overlay to map and reach its final geometry before starting
    `gpu-screen-recorder`;
  - preserve cleanup on cancellation, start failure, stop and interruption;
  - validate the real webcam path in a desktop/VM at multiple output scales and
    inspect a captured frame before marking complete.

Monarch now gives its `mpv` overlay shape-specific window identities, Niri-side
circle clipping, proportional presets and capture-region-aware placement. It
waits for the exact mapped geometry before recording, supports keyboard and
mouse resizing, and cleans up by the recorded process identity. VM validation
covered circle and rectangle rendering, 1x and 1.5x output scales, focus
retention and live resizing; `gpu-screen-recorder` itself cannot run with the
VM's AMD-safe llvmpipe renderer and still needs one hardware-GPU smoke test.

### Q18 — Test suite triage and rationalization

- **Status:** merged ([#179](https://github.com/monarch-os/monarch/pull/179))
- **Scope:** make the test suite faster, clearer and cheaper to maintain without
  reducing meaningful behavioral coverage.
- **Acceptance criteria:**
  - inventory tests by feature, risk, runtime and execution environment;
  - identify duplicate assertions, obsolete compatibility cases and tests that
    verify implementation details instead of public behavior;
  - consolidate shared fixtures and helpers without creating hidden coupling;
  - define focused, integration and full-suite entry points with deterministic
    ownership and documented expectations;
  - remove or merge tests only after proving the retained coverage exercises
    the same failure modes;
  - record before/after runtime, test count and coverage decisions.

Q18 inventories the original 50 executable tests by feature, risk and
environment and adds focused, deterministic integration and full-suite entry
points. Milestone-named coverage was merged into its owning
suites; low-value package-recipe assertions were removed after review, leaving
49 Monarch tests. CI now runs all 48 repository-local tests instead of 10
unique files, keeps external
repository availability isolated in its own job, and removes a duplicate Niri
run plus the redundant standalone route check. No behavioral test was removed:
the menu suite reuses one declaration snapshot and one evaluated-state snapshot,
and unused Hyprland/Quickshell test helpers are gone. On the development machine,
the old serial inventory took
164 s with five environment-related failures; the retained integration suite
passes in 25.7 s and the 49-test full suite passes in 28.4 s with four workers.

### Q19 — Migration optimization and reduction

- **Status:** merged ([#180](https://github.com/monarch-os/monarch/pull/180));
  `monarch` and `monarch-settings` published as
  `0.12.0.r108.g65891ad-1`
- **Scope:** reduce migration volume and update cost before Noctalia v5 is
  deployed, while preserving the migrations that still represent supported
  installation states.
- **Acceptance criteria:**
  - inventory migrations by supported source state, side effects, dependencies
    and continued relevance;
  - remove migrations that can only target an installation state that has
    never shipped, rather than carrying speculative compatibility;
  - fold compatible operations into current defaults, install phases or a
    smaller number of idempotent migrations when that makes ownership clearer;
  - preserve ordering where one retained migration genuinely depends on
    another and keep update interruption safe;
  - avoid repeated package, config refresh and privileged operations across the
    retained migration path;
  - prove fresh installation and every supported upgrade starting point reach
    the same final state, with before/after migration count and runtime.

The timestamped migration model is removed rather than compacted. Updates now
run `monarch-reconcile`, which first bootstraps the `monarch` and
`monarch-settings` packages and then converges the supported system and user
states through fixed, idempotent reconcilers. Future compatibility logic is
owned by domain in those reconcilers and removed when its source state leaves
the supported upgrade window; it no longer creates one permanent file per
change.

Support is bounded by one installation schema in
`~/.local/state/monarch/schema`: current schema 2, minimum supported schema 1.
Schema 1 is the historical checkout model; schema 2 is the packaged runtime.
Fresh installs record 2 directly; unversioned checkout installs must prove the
last supported v4 migration marker before being inferred as schema 1. Older
states are told to update through v4 first, and schemas newer than the running
code are never downgraded. Schema 2 is committed atomically only after both
deferred transition hooks have completed.

The v4 path restores the complete Noctalia transition that the packaged-runtime
refactor had accidentally deleted: install v5 before removing `noctalia-shell`,
replace incompatible config and cache state, preserve fingerprint enablement,
seed every palette and plugin, refresh Niri, and enable plugins immediately or
through a retrying post-boot hook. It also applies the SSH PATH and fingerprint
PAM repairs that existing installs do not receive from fresh-install stages.

The old `~/.local/share/monarch` checkout remains in place for the update that
is executing from it. On the next desktop boot it is moved atomically to
`~/.local/share/monarch-v4` and replaced with a compatibility symlink to
`/usr/share/monarch`; historical migration markers are then removed. Stock
shell and UWSM references are rewritten before that finalization. Packaged
updates skip Git, while source checkouts retain Git and dev-channel behavior.

The runtime packages are now published from `monarch-pkgs` PR #64, with the
x86_64 builders aligned on CachyOS by `monarch-pkgs-builder` PR #6 and
`monarch-pkgs` PR #69. The isolated suite passes 49/49 in 25.7 s, and focused
tests cover legacy-state cleanup, immediate/deferred plugin activation,
repeated convergence, runtime path rewriting, checkout archival and update
ordering. A normal ISO build without `--local-source` also passes and bundles
the published `0.12.0.r108.g65891ad-1` package pair. Installing that ISO also
passes: the machine boots from Btrfs with schema 2, the packaged runtime, no
legacy checkout and no failed units. PR #181 corrected the runtime path used by
AZERTY keyboard regeneration and made all three repository keyrings explicit
target packages populated during finalization. On a fresh VM, the CachyOS key
has full trust, `pacman -Syy` and `monarch-update-keyring` succeed, and two
successive reconciliations plus Niri validation pass.

### Q20 — Decommission monarch-welcome

- **Status:** `monarch` merged — PR #187; package retirement pending in
  `monarch-pkgs`.
  to the follow-up `monarch-pkgs` change.
- **Scope:** remove the standalone onboarding TUI now that its application
  catalogue, setup checklist and desktop tour overlap the Monarch menu and
  current setup flows.
- **Acceptance criteria:**
  - fresh installations do not install or launch `monarch-welcome`;
  - the first Noctalia-ready theme application remains intact;
  - obsolete Niri rules are removed;
  - retire the package recipe only after the core change is merged;
  - archive the source repository only after a replacement ISO is validated.
  - revisit onboarding as a separate product-design task, using the existing
    menu, notifications and setup surfaces before considering another app.

The core change moves the first theme application into its own first-run script
and removes the package from the base set. No reconciliation is added because
Noctalia v5 has not been deployed to users. The package remains published until
the ordered `monarch-pkgs` follow-up.

Removing `monarch-welcome` does not mean Monarch no longer needs onboarding.
Reassess what a first-time user must discover, which steps deserve active
guidance and how progress should be surfaced. Start from native Noctalia and
Monarch interactions; do not assume the replacement should be a standalone TUI.

### Q21 — Quattro 4.0.0–4.0.2 release-gap closure

- **Status:** audited against `origin/noctalia-v5@ff9f94293`, Quattro v4.0.0
  `f0020448c`, v4.0.1 `13f18b2cb` and v4.0.2 `346e69e1c`; implementation in
  progress. Plymouth/SDDM publication is hardened and validated in a clean VM;
  the remaining items below are pending.
- **Scope:** close security and correctness gaps first, repair accidental
  regressions, then make explicit product decisions for optional Quattro
  features. Current Quattro head `f99d33a8d` is included so this does not become
  another stale tag-only snapshot.
- **Research:** `QUATTRO-4-RELEASES-AUDIT.md` records the release-by-release
  evidence and covered/equivalent/not-applicable classifications.

#### P0 — privileged boundaries and remotely influenced input

- **Done:** remove `monarch-sudo-reset`. The command interpolated
  caller-controlled `$USER` into `su -c`; package upgrades now retire both the
  runtime file and its `/usr/bin` symlink, and regression coverage keeps the
  source and dispatcher route absent.
- **Done:** publish Plymouth and SDDM inputs through root-owned staging with a
  fixed allowlist, validated sources and atomic replacement. Destination files
  are now `root:root 0644`; hostile source/destination symlinks and writable
  destination parents are covered by regression tests.
- **Done:** SSH setup now authorizes and verifies a usable key before publishing
  a key-only drop-in or exposing the daemon. Global and owner-context OpenSSH
  settings are validated before startup; reconciliation is limited to
  Monarch-marked, single-login-identity servers and leaves administrator setups
  intact whenever key-only access cannot be proven without a lockout.
- Stop granting `input` by default and replace the blanket wheel-wide
  `NOPASSWD: /usr/bin/asdcontrol` rule with the narrowest workable boundary.
- Disable automatic remote printer discovery. If `cups-browsed` remains an
  option, ship a hardened opt-in configuration instead of
  `CreateRemotePrinters Yes`.
- Harden Windows VM storage and launch handling: validate all user-supplied
  values, keep host mounts behind an explicit protected boundary, pin immutable
  inputs where practical, and make cleanup operate only on resolved VM-owned
  paths.
- Validate web-app names, URLs and icon media; reject path separators and
  non-HTTP(S) URLs, escape Desktop Entry values, and remove from recorded paths
  rather than reconstructing paths from the display name. Apply the same
  shell-argument discipline to app/font install helpers.

#### P1 — release regressions and hardening helpers

- Restore the XPS speaker-tuning implementation or delete its dead installer
  hook. `install/hardware/speaker-tuning.sh` calls `monarch-audio-tuning`, but
  neither that command nor `default/audio/` exists on `origin/noctalia-v5`, so
  the advertised tuning silently never applies.
- Reject an empty replacement LUKS password and require confirmation before
  invoking `cryptsetup luksChangeKey`.
- Detect NVIDIA hardware through sysfs vendor/class/device IDs without waking a
  suspended discrete GPU; do not depend on `lspci` marketing-name regexes.
  Bound `supergfxctl` probes so a stuck daemon cannot hang the menu.
- Centralize internal-panel detection and recognize LVDS as well as eDP.
- Treat OWE Wi-Fi as passwordless. The network plugin currently classifies any
  non-empty security label as credentialed and opens a password prompt.
- Reconcile installations where the old iwd transition left `wpa_supplicant`
  masked, including runtime masks and the NetworkManager recovery path.
- Force a stable numeric locale for the network speed test so Luau receives a
  decimal point on every locale.
- Complete or remove the advertised opt-in sudoless-Docker flow. The default
  group grant is correctly gone, but the documented setup/remove commands and
  menu toggle do not exist.
- Restore controlled recovery from Pacman conflicts: quarantine only confirmed
  unowned files, rollback on failure, and make the retry an explicit user
  decision.
- Add the hardened Apple-brightness query/retry/cache path, the default-browser
  MIME fallback, and Chromium's `gnome-libsecret` password-store flag. The
  Chromium first-run EULA preference is already covered.
- Add an installed-tree acceptance target, privileged-heredoc/static boundary
  checks, and repository security ownership guidance. PRs #191–#196 repair the
  known legacy files but do not guard the pattern from returning.

#### P2 — explicit product choices, not automatic parity work

- Evaluate a Niri-native window layout save/restore flow and keyboard-driven
  screenshot target selection.
- Decide whether the default product wants active-window, weather, dedicated
  microphone and richer media widgets; Fireworks usage and Google Meet picture-
  in-picture; captive-portal handling; or Hermes integration.
- Decide separately whether to add Quattro's small default utilities and
  services (`udiskie`, `mpv-mpris`, `yt-dlp`, `dua-cli`, Docker multi-arch
  binfmt). Moonlight already has an optional installer and need not become a
  default merely for parity.
- Keep Dropbox, ONCE and Sunshine under their existing decisions. Keep native
  Noctalia clipboard/history, themes, panels and plugin lifecycle instead of
  porting Quattro's QML/Hyprland implementation details.

#### Confirmed covered or not applicable

- v4.0.0's shell foundation is covered by Noctalia or Monarch equivalents:
  unified bar/control centre, notifications and history, clipboard/emoji,
  palette and wallpaper integration, movable compact bar, nested menu,
  text scaling, DDC brightness, QR sharing, Tailscale/Taildrop, Claude/Codex
  usage, owner provisioning, factory reset, disk preflight, zram, systemd-oomd
  and per-source power profiles.
- v4.0.1's agent auto-review, FIDO staging, structured notification arguments,
  data-only theme import, DNS helper PATH/polkit fallback, opt-in Docker group,
  Taildrop waiting, quiet mise wrapper and psmouse tolerance are covered.
- v4.0.2's browser-policy hardening and removal of legacy v4 privileged files
  are covered by PRs #190–#196; Monarch's repository already requires package
  signatures. Hyprland Lua, Quickshell QML image loading and Quattro plugin-
  cloning fixes do not map to the Niri/Noctalia architecture.

Acceptance requires focused regression tests for every P0/P1 item, the full CLI
and menu suites, installed-tree execution for privileged checks, and a fresh VM
install for SSH, printing, display-manager, Plymouth, input, audio and GPU paths.

## Deferred

- Use the `bypass_dnd` directive for urgent notifications such as low-battery
  warnings.
- Firefox/pywalfox integration.
- Replacing Noctalia's native wallpaper or application picker.
- A full Quattro-style user-authored shell or bar-plugin architecture.

## References

- [Quattro bar manual](https://github.com/basecamp/omarchy/blob/4cd8a081cb67af345be7d8677faeee6575d89bef/manual/05-the-top-bar.md)
- [Quattro plugin manual](https://github.com/basecamp/omarchy/blob/4cd8a081cb67af345be7d8677faeee6575d89bef/manual/32-shell-plugins.md)
- [Quattro background manual](https://github.com/basecamp/omarchy/blob/4cd8a081cb67af345be7d8677faeee6575d89bef/manual/39-backgrounds.md)
- [Quattro theme authoring](https://github.com/basecamp/omarchy/blob/4cd8a081cb67af345be7d8677faeee6575d89bef/manual/43-making-your-own-theme.md)

## Validation

```bash
bash test/monarch-cli-test.sh
bash test/monarch-menu-test.sh
bin/monarch commands --check
bin/monarch-menu --check
```

For desktop changes, deploy to the dev VM, exercise the real path, capture and
inspect a screenshot. Keep this document uncommitted unless explicitly asked.
