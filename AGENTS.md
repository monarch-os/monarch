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

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `menu-`, `migrate-`, `niri-`, `notification-`, `npx-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `swayosd-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

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
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, color0-15)

# Visual Changes

When making visual changes, such as Waybar styles or desktop appearance, always take and analyze a screenshot after applying the change to verify the result. Use `monarch capture screenshot fullscreen save` for fullscreen screenshots.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
monarch-refresh-config hyprlock/hyprlock.conf
```

This copies `~/.local/share/monarch/config/hyprlock/hyprlock.conf` to `~/.config/hyprlock/hyprlock.conf`.

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
- **Compositor: Monarch replaces Hyprland with Niri.** Hyprland-the-compositor and its tightly-coupled daemons (`hypridle`, `hyprsunset`, `xdg-desktop-portal-hyprland`) are dropped in favour of `niri`, `swayidle`, `wlsunset`, and `xdg-desktop-portal-gnome`. `hyprlock` and `hyprpicker` are kept — both are wlroots-compatible (`ext-session-lock-v1` / wlr-screencopy) and run cleanly under Niri without the rest of the Hyprland stack. Configs live under `config/niri/`, `default/niri/`, `config/swayidle/`, `config/hyprlock/`, `config/wlsunset/`. During upstream syncs, drop any new Hyprland compositor configs that come from Omarchy and keep their Niri equivalents.

After a sync, run `bash test/monarch-cli-test.sh` and `bin/monarch commands --check` to validate metadata and routes.
