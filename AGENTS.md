# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` and `migrations/` may be sourced and intentionally omit shebangs

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

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `menu-`, `migrate-`, `niri-`, `notification-`, `npx-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

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
- keep hardware-specific logic under `install/config/hardware/`
- prefer helper commands for package and command checks where available

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in bootstrap/preflight/package-helper contexts where the helper commands may not be available yet or where direct package-manager behavior is the point of the script.

# Helper Commands

Use these instead of raw shell commands:

- `monarch-cmd-missing` / `monarch-cmd-present` - check for commands
- `monarch-pkg-missing` / `monarch-pkg-present` - check for packages
- `monarch-pkg-add` - install packages (handles both pacman and AUR)
- `monarch-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for bootstrap, preflight, migration, and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `config/noctalia/colorschemes/Monarch/Monarch.json` - the single Monarch color scheme (`dark` + `light` blocks); Noctalia owns colors and dark/light
- `config/noctalia/templates/` + `config/noctalia/user-templates.toml` - Noctalia user-template inputs for the apps without a built-in template (neovim, obsidian)
- `themes/<scheme>/` - per-Noctalia-scheme wallpaper sets (flat layout, the only surviving `themes/` content); seeded into `~/.config/monarch/backgrounds/<scheme>/` by `monarch-theme-apply`

# Theming

Theming is delegated to Noctalia (see `THEMING_MIGRATION_PLAN.md`). Noctalia is the source of truth for colors, dark/light, app templates, wallpaper, and the shell. Monarch's home-grown theme engine (curated theme set, `default/themed/*.tpl`, per-theme `colors.toml`, `monarch-theme-set` and friends) has been removed.

- Colors: Monarch ships a single scheme `Monarch` (`config/noctalia/colorschemes/Monarch/Monarch.json`, `dark` + `light` blocks). Noctalia's built-in schemes (Catppuccin, Gruvbox, Nord, …) remain selectable in its picker.
- Dark/light: Noctalia's global toggle (`colorSchemes.darkMode`). GTK/Qt follow natively via `colorSchemes.syncGsettings`. Nothing in Monarch flips `darkMode`.
- App theming: terminals (alacritty/kitty/foot/ghostty), btop, helix, niri, VSCode (NoctaliaTheme extension), and Firefox (pywalfox) use **native Noctalia templates**. neovim and obsidian use Noctalia **user-templates** (`config/noctalia/templates/`, registered in `config/noctalia/user-templates.toml`).
- Residual layer: the only remaining Monarch piece is `bin/monarch-theme-apply` (`monarch theme apply`), wired to Noctalia's `hooks.colorGeneration`. It re-applies what Noctalia can't reach — wallpaper folder, keyboard RGB (asusctl/qmk_hid), Chromium policy color, and Plymouth (interactive only) — deriving colors from the active scheme JSON. It never writes `darkMode`.

# Visual Changes

When making visual changes, such as Noctalia bar/widget tweaks or desktop appearance, always take and analyze a screenshot after applying the change to verify the result. Use `monarch capture screenshot fullscreen save` for fullscreen screenshots.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
monarch-refresh-config noctalia/settings.json
```

This copies `~/.local/share/monarch/config/noctalia/settings.json` to `~/.config/noctalia/settings.json`.

For the Niri compositor specifically, prefer `monarch-refresh-niri` — it rebuilds `~/.config/niri/config.kdl` by concatenating the Monarch default, the current theme overlay, and the user override (`~/.config/niri/user.kdl`), then validates and reloads.

# Migrations

To create a new migration, run `monarch-dev-add-migration --no-edit`. This creates a migration file named after the unix timestamp of the last commit.

New migration format:
- File permissions must be `0644` (`-rw-r--r--`); migrations are sourced, not executed directly
- No shebang line
- Start with an `echo` describing what the migration does
- Use `$MONARCH_PATH` to reference the monarch directory
- Prefer helper commands such as `monarch-cmd-present`, `monarch-cmd-missing`, `monarch-pkg-present`, and `monarch-pkg-missing`

Some older migrations predate these rules. Do not copy older migrations that start with shebangs, omit the leading `echo`, or hard-code `~/.local/share/monarch`.

Migrations may use raw `pacman`, `command -v`, or direct config edits when needed for historical compatibility or one-off repair work.

Example:
```bash
echo "Drop fingerprint marker if no fingerprint device is enrolled"

if monarch-cmd-missing fprintd-list || ! fprintd-list "$USER" 2>/dev/null | grep -q "finger"; then
  rm -f "$HOME/.local/state/monarch/fingerprint-enabled"
fi
```

# Upstream Sync

Monarch is a fork of [Omarchy](https://github.com/basecamp/omarchy) and tracks upstream releases via the `omarchy` git remote. The sync renames `omarchy*` → `monarch*` (binaries, paths, `# omarchy:` metadata directives, env vars like `OMARCHY_PATH`).

Some `omarchy` references are intentional and must be preserved:

- AUR package names: `omarchy-keyring`, `omarchy-chromium`
- Historical migration text that documents past upstream behavior

When Monarch diverges from upstream, mark it clearly:

- `bin/monarch-branch-set` only supports `master|dev` (no `rc` channel)
- `test/monarch-cli-test.sh` may need assertion adjustments to match Monarch divergences after a sync
- Some upstream commands (cliamp, etc.) are intentionally not shipped — skip the corresponding migrations
- **Compositor: Monarch replaces Hyprland with Niri.** Hyprland-the-compositor and its tightly-coupled daemons (`hypridle`, `hyprsunset`, `xdg-desktop-portal-hyprland`) are dropped in favour of `niri`, `wlsunset`, and `xdg-desktop-portal-gnome`. Only `hyprpicker` is kept (wlr-screencopy color picker) and runs cleanly under Niri. Configs live under `config/niri/`, `default/niri/`. Night light is owned by Noctalia (`nightLight` IPC / `settings.json`), which spawns `wlsunset` itself, so Monarch ships no wlsunset config. Idle (screensaver / lock / DPMS) is owned by Noctalia's `IdleService` (`idle.*` in `settings.json`); lid-close lock is a niri `switch-events` block (`default/niri/power.kdl`). During upstream syncs, drop any new Hyprland compositor configs that come from Omarchy and keep their Niri equivalents.
- **Desktop shell: Noctalia (Quickshell) replaces waybar + walker + mako + hyprlock + swayosd + swaybg.** A single `qs -c noctalia-shell` process provides the bar, launcher, notifications, control center, lock screen, OSDs and wallpaper management. Driven via IPC (`qs -c noctalia-shell ipc call <target> <function> [args...]`); see `default/monarch-skill/SKILL.md` for the target reference. User config lives at `~/.config/noctalia/settings.json`. `fuzzel` provides the dmenu picker used by `monarch-menu` and friends. During upstream syncs, drop any waybar/walker/mako/hyprlock/swayosd configs that come from Omarchy and surface their equivalents through Noctalia instead.
- **Theming: delegated to Noctalia.** Monarch's home-grown theme engine is removed (no curated theme set, no `default/themed/*.tpl`, no per-theme `colors.toml`, no `monarch-theme-set`/`-list`/`-current`/`-install`/`-bg-*` and no `theme-set` hook). Monarch ships only the single scheme `config/noctalia/colorschemes/Monarch/Monarch.json` (`dark` + `light`); colors, dark/light, app templates and wallpaper are owned by Noctalia. The lone residual is `monarch-theme-apply` (`monarch theme apply`), wired to `hooks.colorGeneration`, for the system layer Noctalia can't reach (wallpaper folder, keyboard RGB, Chromium policy color, Plymouth). See the **Theming** section above and `THEMING_MIGRATION_PLAN.md`. During upstream syncs, do not reintroduce Omarchy's theme scripts/templates; route theming through Noctalia.

After a sync, run `bash test/monarch-cli-test.sh` and `bin/monarch commands --check` to validate metadata and routes.
