# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` may be sourced and intentionally omit shebangs

# Git Worktrees

Create worktrees inside the repository currently being modified, under its
`.worktrees/` directory. Do not create sibling worktree directories in the
workspace root.

For example, work on branch `feature/bar-position` in this repository with:

```bash
git worktree add .worktrees/bar-position -b feature/bar-position origin/noctalia-v5
```

Apply the same rule independently in every workspace repository: a
`monarch-pkgs` worktree belongs under `monarch-pkgs/.worktrees/`, not under
`monarch/.worktrees/` or beside the repositories.

# Command Naming

All commands start with `monarch-`. Prefixes indicate purpose.

The authoritative command group list lives in `bin/monarch` in `GROUP_DESCRIPTIONS`. Keep `GROUP_DESCRIPTIONS` updated when adding a new command prefix.

Common prefixes include:

- `cmd-` - check if commands exist, misc utility commands
- `capture-` - screenshots, screen recordings, and other capture tools
- `pkg-` - package management helpers
- `hw-` - hardware detection (return exit codes for use in conditionals)
- `refresh-` - copy default config to user's `~/.config/`
- `restart-` - restart a component
- `launch-` - open applications
- `install-` - install optional software
- `setup-` - interactive setup wizards
- `toggle-` - toggle features on/off
- `theme-` - theme management
- `update-` - update components

Other current prefixes include:

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `menu-`, `migrate-`, `niri-`, `notification-`, `npx-`, `plymouth-`, `powerprofiles-`, `reconcile-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

# Command Metadata

Commands in `bin/` can declare CLI metadata in comments near the top of the file. `bin/monarch` scans the first 80 lines, and tests expect command metadata to remain valid.

Supported metadata keys:

- `# monarch:summary=...` - short help text
- `# monarch:group=...` - command group when it differs from the filename-derived prefix
- `# monarch:name=...` - command name within the group
- `# monarch:args=...` - usage arguments
- `# monarch:examples=...` - examples separated with ` | `
- `# monarch:alias=...` / `# monarch:aliases=...` - alternate routes
- `# monarch:hidden=true` - hide from default command listings
- `# monarch:requires-sudo=true` - mark commands that require sudo

Prefer explicit metadata for user-facing commands. Keep routes consistent with the filename unless there is a deliberate alias or compatibility route.

Example:

```bash
# monarch:summary=Take a screenshot
# monarch:group=capture
# monarch:args=[smart|region|windows|fullscreen] [slurp|copy]
# monarch:examples=monarch screenshot | monarch capture screenshot region
# monarch:aliases=monarch screenshot
```

# Install Scripts

Install entry points (`install.sh`, `boot.sh`) use `#!/bin/bash`. Many scripts under `install/` are sourced via `run_logged` and intentionally do not have shebangs.

Install stage files follow this pattern:

- `install/*/all.sh` lists scripts in execution order
- leaf scripts are sourced by `run_logged $MONARCH_INSTALL/path/to/script.sh`
- avoid `exit` in sourced install scripts unless intentionally aborting the install
- use `$MONARCH_INSTALL` and `$MONARCH_PATH` instead of hard-coded Monarch paths
- keep root hardware logic under `install/hardware/` and session-dependent fixes under `install/user/hardware/`
- prefer helper commands for package and command checks where available

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in bootstrap/preflight/package-helper contexts where the helper commands may not be available yet or where direct package-manager behavior is the point of the script.

# Helper Commands

Use these instead of raw shell commands:

- `monarch-cmd-missing` / `monarch-cmd-present` - check for commands
- `monarch-pkg-missing` / `monarch-pkg-present` - check for packages
- `monarch-pkg-add` - install packages (handles both pacman and AUR)
- `monarch-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for bootstrap, preflight, reconciliation, and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `config/noctalia/config.toml` - Monarch's Noctalia defaults (theme, bar lanes, per-widget settings, hooks, idle). Noctalia merges *every* `*.toml` in `~/.config/noctalia/`, and keeps its own mutable state in `~/.local/state/noctalia/settings.toml` — never ship that file.
- `config/noctalia/palettes/Monarch.json` - the single Monarch color scheme (`dark` + `light` blocks, plus a `terminal` block of ANSI colors); Noctalia owns colors and dark/light
- `config/herdr/config.toml` - herdr's config, shipped whole and never re-rendered: herdr queries the terminal for its palette over OSC, so `theme = "terminal"` plus ANSI slot names follow the scheme unaided. `monarch refresh herdr` restores the shipped file.
- `default/noctalia/plugins/` - Luau plugins, seeded to `~/.local/share/noctalia/plugins/` (NOT `~/.config/`) by `monarch-settings`
- `default/noctalia/indicators/` - the shell scripts the bar indicators stream; each emits one JSON object per line
- `themes/<scheme>/` - per-Noctalia-scheme wallpaper sets (flat layout, the only surviving `themes/` content); seeded into `~/.config/monarch/backgrounds/<scheme>/` by `monarch-theme-apply`

# Menu

**The menu is data, not code.** `default/monarch/monarch-menu.jsonc` holds the
tree; the `monarch/menu` Noctalia panel draws it; `bin/monarch-menu` loads the
data for the panel and routes the keybinds to it. Adding a menu entry means
editing the `.jsonc`, never the renderer.

- IDs are object keys and **the dotted ID is the tree** — `trigger.share.file`
  is a child of `trigger.share`. There is no parent field to keep in sync.
- Kind is inferred: `action` → action, `target` → link, otherwise submenu.
  Guards are `when` (hide), `checked` (append ✓), `disabled` (listed but inert).
- The user overlays `~/.config/monarch/extensions/monarch-menu.jsonc`, merged per
  key *and per field*, so reusing a shipped ID overrides only what it declares
  and keeps its position. New IDs append. The sample lives in
  `config/monarch/extensions/`.
- Routes resolve exact ID → alias → last ID segment, so `monarch menu style` and
  `monarch menu trigger.capture` both work and new entries rarely need an alias.
  **Watch the group collision**: `monarch menu share` dispatches to the
  `monarch-menu-share` *command*, not to the menu's `trigger.share` route —
  `monarch-menu share` is the one that opens the menu there.
- Anything a row cannot express as one shell command belongs in a command of its
  own (`monarch-capture-screenrecording-with-webcam`, `monarch-reminder -i`),
  because actions run detached and cannot call helpers defined in the renderer.
- Dynamic rows come from a `provider` (`fonts`, `power-profiles`), defined in the
  renderer's `PROVIDER_*` maps. Data can point at one but cannot declare one.

Install rows carry `disabled` with a presence check, so software already on the
machine reads as installed instead of vanishing — the list stays a catalog of
what Monarch can install. Remove rows are the opposite and hide with `when` what
is not there to remove.

The panel (`default/noctalia/plugins/monarch-menu/`) never parses the JSONC: it
calls `monarch-menu --state` for the tree and every guard in one payload, and
`--provider <id>` for runtime rows. The same tree is exposed to the global
launcher by the plugin's `[[launcher_provider]]` entry (`/mm`). **Do not cache
the tree across opens** — editing the JSONC or the user's extension would then
change nothing until the shell restarted; `--state` is one subprocess and the
guards have to be re-read anyway. Two hard-won constraints govern any panel
work:

- **A plugin callback has a small CPU budget and the host kills the callback that
  exceeds it.** The cost that matters is per-callback total, so do the expensive
  things once and index them: decoding 38 kB of JSON and indexing 266 entries is
  ~3 ms, but deriving a level's children by scanning every entry made `isVisible`
  quadratic (~70 000 pattern matches) and was killed every time. Build lookups in
  the load pass, never per level.
- **Anything per-entry must be a native call, not a Luau loop.** The guards come
  back as a JSON object keyed `<id>:<w|c|d>` precisely so `json.decode` builds
  it; parsing the same 130 lines in Luau blew the budget. Search results are
  capped and breadcrumbs memoised for the same reason — `onQueryChanged` fires
  per keystroke.
- **`ui.box` takes no children** — wrapping a row in one silently drops
  everything inside it (`ui tree: 'box' cannot have children`). Rows carry their
  own `fill`/`radius`/`padding`.

Escape is consumed by the host and closes the panel, so back-navigation is Left
(and clearing the search field), never Escape.

Validate with `bin/monarch-menu --check` (dangling targets, unknown providers,
orphaned parents, childless submenus) and `bash test/monarch-menu-test.sh`, which
covers the data layer and the payloads the panel consumes. `--resolve <route>`
and `--rows <id>` print what a level resolves to without opening a window.

# Theming

Theming is delegated to Noctalia (see `THEMING_MIGRATION_PLAN.md`). Noctalia is the source of truth for colors, dark/light, app templates, wallpaper, and the shell. Monarch's home-grown theme engine (curated theme set, `default/themed/*.tpl`, per-theme `colors.toml`, `monarch-theme-set` and friends) has been removed.

- Colors: Monarch ships `Monarch` plus the 22 Omarchy Quattro palettes, all under `config/noctalia/palettes/` and selected by `[theme] source = "custom"` + `custom_palette = "<Name>"` (default `Monarch`). Each carries the same block under both `dark` and `light` — these themes have one appearance, and Noctalia rejects a custom palette whose active-mode block is missing. Noctalia's ten built-in schemes remain selectable in its picker and are untouched; they ship no palette JSON, so the colour-derived parts of `monarch-theme-apply` no-op for them.
- Dark/light: Noctalia's global toggle (`[theme] mode`, or `noctalia msg theme-mode-toggle`). Nothing in Monarch flips it.
- App theming: prefer catalog ids. `[theme.templates] builtin_ids` covers alacritty, kitty, foot, ghostty, btop, helix, niri and starship; `community_ids` covers fuzzel, neovim, obsidian, zed and vscode. The `enable_builtin_templates` / `enable_community_templates` switches are master toggles only — **an id absent from the arrays is never rendered however true they are.** A template whose client is not installed is skipped silently, so listing them all is safe.
- Obsidian vaults: `monarch-obsidian-theme.path` watches Obsidian's vault registry and reapplies the community template when it changes. The oneshot verifies both the generated snippet and its activation before succeeding; no daemon or polling loop is added.
- User templates: Noctalia accepts `[theme.templates.user.<id>]` in any user `*.toml` overlay. Use static `input_path` and `output_path` for data-only templates; `pre_hook`, `post_hook` and `output_path_dynamic` execute trusted local code. A user entry is applied after catalog templates but does not shadow one by id, so remove the replaced id from `builtin_ids` or `community_ids` first. Keep remotely installed Q5 bundles separate and code-free. Herdr needs no template because it queries the terminal palette over OSC. SDDM remains outside the catalog; `monarch-sddm-apply` renders its `theme.conf` and logo from `monarch-theme-colors`.
- Residual layer: `bin/monarch-theme-apply` (`monarch theme apply`) is wired to Noctalia's `[hooks] colors_changed`. It re-applies what Noctalia can't reach — wallpaper folder, keyboard RGB (asusctl/qmk_hid), and Chromium policy color — reading the active scheme via `noctalia msg color-scheme-get` / `theme-mode-get`. SDDM and Plymouth are selected together through the interactive Unlock gallery because applying Plymouth rebuilds the initramfs. The residual hook never writes the theme mode or either unlock screen.
- Wallpaper caveat: v5 has no IPC to change the wallpaper *directory* (only `wallpaper-set/get/next/previous/random`), so the per-scheme folder repointing v4 did is gone. `[wallpaper] directory` is pinned to Monarch's folder in `config.toml`.

# Visual Changes

When making visual changes, such as Noctalia bar/widget tweaks or desktop appearance, always take and analyze a screenshot after applying the change to verify the result. Use `monarch capture screenshot fullscreen save` for fullscreen screenshots.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
monarch-refresh-config noctalia/config.toml
```

This copies `/usr/share/monarch/config/noctalia/config.toml` to `~/.config/noctalia/config.toml`.

For the Niri compositor specifically, prefer `monarch-refresh-niri` — it rebuilds `~/.config/niri/config.kdl` by concatenating the Monarch default, the current theme overlay, and the user override (`~/.config/niri/user.kdl`), then validates and reloads.

# Reconciliation

`monarch-reconcile` converges supported installations onto the current state
after packages are updated. Do not add timestamped migrations. Put privileged,
idempotent ownership in `install/reconcile/system.sh` and user/session ownership
in `install/reconcile/user.sh`. A schema transition may add
`system-after-user.sh` when destructive system cleanup must wait until its user
replacement exists.

Reconcilers must detect the state they own, tolerate repeated execution and
stop before destructive cleanup if their replacement is unavailable. Remove a
legacy branch once its source state falls outside the supported upgrade window.
Use `$MONARCH_PATH` for the packaged runtime and `$MONARCH_SOURCE_ROOT` only when
the checkout that bootstrapped the transition matters.

`~/.local/state/monarch/schema` records one installation schema, not individual
changes. Bump it only for an architectural transition that needs a distinct
upgrade path, keep `CURRENT_SCHEMA` and `MIN_SUPPORTED_SCHEMA` explicit in
`monarch-reconcile`, and write the new value only after deferred work completes.
An unversioned legacy install must prove the documented floor marker before it
is treated as the minimum supported schema.

# Upstream Sync

Monarch is a fork of [Omarchy](https://github.com/basecamp/omarchy) and tracks upstream releases via the `omarchy` git remote. The sync renames `omarchy*` → `monarch*` (binaries, paths, `# omarchy:` metadata directives, env vars like `OMARCHY_PATH`).

Some `omarchy` references are intentional and must be preserved:

- AUR package names that still encode the upstream name

When Monarch diverges from upstream, mark it clearly:

- `bin/monarch-branch-set` only supports `main|dev` (no `rc` channel)
- `test/monarch-cli-test.sh` may need assertion adjustments to match Monarch divergences after a sync
- Some upstream commands (cliamp, etc.) are intentionally not shipped — skip their reconciliation logic
- **Compositor: Monarch replaces Hyprland with Niri.** Hyprland-the-compositor and its tightly-coupled daemons (`hypridle`, `hyprsunset`, `xdg-desktop-portal-hyprland`) are dropped in favour of `niri`, `wlsunset`, and `xdg-desktop-portal-gnome`. Only `hyprpicker` is kept (wlr-screencopy color picker) and runs cleanly under Niri. Configs live under `config/niri/`, `default/niri/`. Night light is owned by Noctalia (`noctalia msg nightlight-toggle` / `[nightlight]`), which spawns `wlsunset` itself, so Monarch ships no wlsunset config. Idle (screensaver / lock / DPMS) is owned by Noctalia's `[idle.behavior.<name>]` blocks in `config.toml`; lid-close lock is a niri `switch-events` block (`default/niri/power.kdl`). During upstream syncs, drop any new Hyprland compositor configs that come from Omarchy and keep their Niri equivalents.
- **Desktop shell: Noctalia v5 replaces waybar + walker + mako + hyprlock + swayosd + swaybg.** v5 is a native C++ rewrite with **no Qt and no Quickshell** — v4 (`noctalia-shell` + `qs -c`) is frozen upstream and gone from Monarch. The `noctalia` daemon (`noctalia -d`, package `noctalia` from Arch `extra`) provides the bar, launcher, notifications, control center, lock screen, OSDs and wallpaper management. Driven via `noctalia msg <command> [args]` over a Unix socket — flat verbs, not v4's `<target> <function>`; see `default/monarch-skill/SKILL.md` for the command reference. User config lives at `~/.config/noctalia/*.toml`. `fuzzel` provides the dmenu picker used by `monarch-menu` and friends (v5 ships its own `noctalia dmenu`, not yet adopted). During upstream syncs, drop any waybar/walker/mako/hyprlock/swayosd configs that come from Omarchy and surface their equivalents through Noctalia instead.
- **Plugins are Luau, not QML.** v5 has no `CustomButton`; a bar entry that runs a command and renders its output is a plugin under `default/noctalia/plugins/`, referenced in the lanes as `<author>/<plugin>:<entry>`. A plugin declares any of **five** entry kinds — `[[widget]]` (bar), `[[panel]]`, `[[launcher_provider]]`, `[[desktop_widget]]`, `[[shortcut]]` — and may declare several in one manifest; bar widgets are simply the only kind Monarch uses today, not the API's ceiling. The authoritative surface is `noctalia.d.luau` at the root of `github.com/noctalia-dev/official-plugins` (declares `noctalia.*`, `barWidget.*`, `panel.*`, `launcher.*`, `desktopWidget.*`, `shortcut.*`, the `ui.*` node set and every entry-point callback); `noctalia plugins lint` checks a manifest offline. Plugin ids are namespaced, so a plugin **cannot override a built-in widget** — you remove the built-in from the lane and put yours in its place. Built-in widgets are tuned instead through top-level `[widget.<id>]` sections. Two traps: `plugin_api` must be **≥ 22** for relative `require()`, whose path must include the `.luau` extension; and the shell runs without Monarch's `bin/` on `PATH`, so every command a plugin launches needs an absolute path.
- **Theming: delegated to Noctalia.** Monarch's home-grown theme engine is removed (no `default/themed/*.tpl`, per-theme `colors.toml`, `monarch-theme-set`/`-list`/`-current`/`-install`/`-bg-*`, or `theme-set` hook). Monarch ships its palette and the Quattro palette set under `config/noctalia/palettes/`; colors, dark/light, app templates and wallpaper are owned by Noctalia. The residual `monarch-theme-apply` (`monarch theme apply`) is wired to `[hooks] colors_changed` for the system layer Noctalia cannot reach: wallpaper folders, keyboard RGB, Chromium policy color, and SDDM. Plymouth stays manual because applying it rebuilds the initramfs. See the **Theming** section above and `THEMING_MIGRATION_PLAN.md`. During upstream syncs, do not reintroduce Omarchy's theme scripts/templates; route theming through Noctalia.

After a sync, run `bash test/monarch-cli-test.sh` and `bin/monarch commands --check` to validate metadata and routes.
