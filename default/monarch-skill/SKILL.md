---
name: monarch
description: >
  REQUIRED for end-user customization of Linux desktop, window manager, or system config.
  Use when editing ~/.config/niri/, ~/.config/noctalia/, ~/.config/alacritty/,
  ~/.config/foot/, ~/.config/kitty/, ~/.config/ghostty/,
  or ~/.config/monarch/.
  Triggers: Niri, window rules, animations, keybindings, monitors, gaps, borders, focus
  ring, opacity, Noctalia bar/launcher/notifications/lock-screen/OSD, terminal config,
  themes, wallpaper, night light, idle, lock screen, screenshots, reminders, layer rules,
  workspace settings, display config, and user-facing monarch commands. Excludes Monarch
  source development in ~/.local/share/monarch/ and `monarch dev` workflows.
---

# Monarch Skill

Manage [Monarch](https://www.monarchlinux.com/) Linux systems - a beautiful, modern, opinionated Arch Linux distribution with Niri.

This skill is for end-user customization on installed systems.
It is not for contributing to Monarch source code.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/niri/` (window rules, keybindings, monitors, etc.)
- Editing ANY file in `~/.config/noctalia/` (bar, widgets, notifications, control center, lock screen)
- Editing terminal configs (alacritty, foot, kitty, ghostty)
- Editing ANY file in `~/.config/monarch/`
- Window behavior, opacity, gaps, borders, focus ring
- Layer rules, workspace settings, display/monitor configuration
- Color schemes, dark/light mode, wallpapers, fonts, appearance changes
- User-facing `monarch` commands (`monarch refresh ...`, `monarch restart ...`, etc.)
- Screenshots, screen recording, reminders, night light, idle behavior, lock screen

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for Monarch development tasks** (editing files in `~/.local/share/monarch/`, creating migrations, or running `monarch dev ...` workflows).

## Critical Safety Rules

**For end-user customization tasks, NEVER modify anything in `~/.local/share/monarch/`** - but READING is safe and encouraged.

This directory contains Monarch's source files managed by git. Any changes will be:
- Lost on next `monarch update`
- Cause conflicts with upstream
- Break the system's update mechanism

```
~/.local/share/monarch/     # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                    # Source scripts (symlinked to PATH)
├── config/                 # Default config templates (incl. noctalia color scheme)
├── themes/                 # Wallpaper backgrounds only (themes/monarch/backgrounds/)
├── default/                # System defaults
├── migrations/             # Update migrations
└── install/                # Installation scripts
```

**Reading `~/.local/share/monarch/` is SAFE and useful** - do it freely to:
- Understand how monarch commands work: `monarch refresh --help` or `cat $(which monarch-refresh-niri)`
- See default configs before customizing: `cat ~/.local/share/monarch/config/noctalia/settings.json`
- Inspect the shipped Monarch color scheme: `cat ~/.local/share/monarch/config/noctalia/colorschemes/Monarch/Monarch.json`
- Reference default Niri settings: `cat ~/.local/share/monarch/default/niri/config.kdl`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/noctalia/` - Noctalia shell, color schemes, and templates (safe to edit)
- `~/.config/monarch/hooks/` - Custom automation hooks

If the request is to develop Monarch itself, this skill is out of scope. Follow repository development instructions instead of this skill.

## System Architecture

Monarch is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Arch Linux** | Base OS | `/etc/`, `~/.config/` |
| **Niri** | Wayland scrollable-tiling compositor/WM | `~/.config/niri/` |
| **Noctalia** | Desktop shell — bar, launcher, notifications, control center, lock screen, OSDs, wallpaper | `~/.config/noctalia/` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **fuzzel** | Lightweight dmenu picker used by `monarch-menu-*` | n/a |

Noctalia is driven entirely through IPC: `qs -c noctalia-shell ipc call <target> <function> [args...]`. Common targets: `launcher`, `controlCenter`, `settings`, `sessionMenu`, `lockScreen`, `notifications`, `volume`, `brightness`, `nightLight`, `wallpaper`, `colorScheme`, `darkMode`.

## Command Discovery

Monarch ships a single `monarch` CLI that dispatches to all `monarch-*` binaries via `monarch <group> <action>`. Always prefer this form — it is self-documenting and stable. The underlying `monarch-*` binaries still exist on `PATH` and remain safe to read for source.

```bash
# List every documented command and its summary
monarch commands

# Show the commands inside a group
monarch refresh --help
monarch restart --help
monarch theme --help

# Show help for a specific command (does not execute it)
monarch theme apply --help

# Machine-readable listing (binary, route, summary, args, aliases)
monarch commands --json

# Read a command's source to understand it
cat $(which monarch-refresh-niri)
```

### Command Groups

Run `monarch --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `monarch refresh` | Reset config to defaults (backs up first) | `monarch refresh noctalia` |
| `monarch restart` | Restart a service/app | `monarch restart noctalia` |
| `monarch toggle` | Toggle feature on/off | `monarch toggle nightlight` |
| `monarch theme` | Re-sync the residual system theming layer (theming itself is in Noctalia) | `monarch theme apply` |
| `monarch install` | Install optional software / packages | `monarch install docker dbs` |
| `monarch launch` | Launch apps | `monarch launch browser` |
| `monarch capture` | Screenshots and recordings | `monarch capture screenshot` |
| `monarch reminder` | Desktop notification reminders | `monarch reminder 15 "Pickup Jack"` |
| `monarch pkg` | Package management | `monarch pkg install <pkg>` |
| `monarch setup` | Initial setup tasks | `monarch setup fingerprint` |
| `monarch update` | System updates | `monarch update` |

## Configuration Locations

### Niri (Window Manager)

```
~/.config/niri/
├── config.kdl    # Generated by monarch-refresh-niri (defaults + theme + user)
└── user.kdl      # Your personal overrides (preserved across upgrades)
```

**Key behaviors:**
- Niri reloads its config automatically when `~/.config/niri/config.kdl` changes on disk.
- To force a reload manually: `niri msg action reload-config` (or `monarch restart niri`).
- To rebuild `config.kdl` from defaults + theme + user override: `monarch refresh niri`.
- Validate a config file before deploying: `niri validate -c ~/.config/niri/config.kdl`.
- The user-editable file is `~/.config/niri/user.kdl` — anything you put there is appended last and overrides earlier sections.

### Noctalia (Desktop Shell)

```
~/.config/noctalia/
├── settings.json                       # Bar layout, widgets, colors/dark-light, general options
├── colorschemes/Monarch/Monarch.json   # The Monarch color scheme (dark + light blocks)
├── templates/                          # User-template inputs (neovim, obsidian)
└── user-templates.toml                 # User-template registry
```

**Key behaviors:**
- The settings panel (Mod+Shift+Comma or `qs -c noctalia-shell ipc call settings toggle`) is the canonical way to tweak Noctalia, including the color scheme picker and the dark/light toggle. Edits to `settings.json` are picked up on shell restart (`monarch restart noctalia`).
- `monarch refresh noctalia` overwrites `settings.json` with Monarch defaults and restarts the shell.
- Noctalia owns all theming: colors, dark/light, app templates, and wallpaper. Monarch ships a single scheme `Monarch` (`colorschemes/Monarch/Monarch.json`, with `dark` and `light` blocks); Noctalia's built-in schemes (Catppuccin, Gruvbox, Nord, …) also appear in the picker. Switch with the picker or `qs -c noctalia-shell ipc call colorScheme set <Name>`.
- Dark/light is Noctalia's global toggle (`colorSchemes.darkMode`); GTK/Qt follow natively (`colorSchemes.syncGsettings`). Toggle via the control center or `qs -c noctalia-shell ipc call darkMode toggle`.
- Useful IPC targets:
  - `launcher toggle | clipboard | emoji | command | windows`
  - `controlCenter toggle`
  - `notifications toggleDND`
  - `volume increase | decrease | muteOutput`
  - `brightness increase | decrease | set <0-100>`
  - `nightLight toggle | setStrength <0-100>`
  - `wallpaper set <path> <monitor|"">` (empty monitor = all outputs)
  - `lockScreen lock`, `sessionMenu toggle`

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `monarch restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `~/.config/fastfetch/config.jsonc` |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |
| noctalia | `~/.config/noctalia/settings.json` |

## Safe Customization Patterns

### Pattern 1: Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config (the generated file is for reference)
cat ~/.config/niri/user.kdl

# 2. Backup before changes
cp ~/.config/niri/user.kdl ~/.config/niri/user.kdl.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Niri:      monarch refresh niri  (rebuilds + reloads; validates first)
# - Noctalia:  monarch restart noctalia
# - Terminals: monarch restart terminal
```

### Pattern 2: Change the theme (delegated to Noctalia)

Theming is owned by Noctalia, not Monarch. There are no Monarch custom themes to create.

- Pick a color scheme: open the Noctalia settings panel (Mod+Shift+Comma) and use the color scheme picker, or `qs -c noctalia-shell ipc call colorScheme set <Name>`. Available schemes are the shipped `Monarch` plus Noctalia's built-ins (Catppuccin, Gruvbox, Nord, …).
- Toggle dark/light globally: control center or `qs -c noctalia-shell ipc call darkMode toggle` (GTK/Qt follow automatically).
- Tweak the Monarch palette: edit `~/.config/noctalia/colorschemes/Monarch/Monarch.json` (it has `dark` and `light` blocks), then re-select it in the picker.
- After a scheme change, Noctalia re-themes apps via its templates. The residual system layer (wallpaper folder, keyboard RGB, Chromium policy color, Plymouth) is re-synced by `monarch theme apply`, which Noctalia runs automatically on its `colorGeneration` hook; you can also run it by hand.

### Pattern 3: Use Hooks for Automation

Create scripts in `~/.config/monarch/hooks/` to run automatically on events:

```bash
# Available hooks (see samples in ~/.config/monarch/hooks/):
~/.config/monarch/hooks/
├── font-set         # Runs after font change
└── post-update      # Runs after `monarch update`
```

Example hook (`~/.config/monarch/hooks/font-set`):
```bash
#!/bin/bash
FONT_NAME=$1
echo "Font changed to: $FONT_NAME"
# Add custom actions here
```

Note: color-scheme changes are handled inside Noctalia (via its `hooks.colorGeneration`, wired to `monarch theme apply`), not via a Monarch `theme-set` hook.

### Pattern 4: Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
monarch refresh noctalia
monarch refresh niri

# The refresh command:
# 1. Backs up current config with timestamp
# 2. Rebuilds config from ~/.local/share/monarch/ defaults + user override
# 3. Reloads the live compositor or restarts the component
```

## Common Tasks

### Themes and color schemes

Theming is handled by Noctalia — Monarch no longer ships theme-management commands.

```bash
# Pick / switch the color scheme (or use the Noctalia settings picker, Mod+Shift+Comma)
qs -c noctalia-shell ipc call colorScheme set <Name>

# Toggle dark/light globally (GTK/Qt follow automatically)
qs -c noctalia-shell ipc call darkMode toggle

# Open the wallpaper picker
qs -c noctalia-shell ipc call wallpaper toggle

# Re-sync the residual system layer (wallpaper folder, keyboard RGB, Chromium, Plymouth).
# Noctalia runs this automatically on a scheme change; run it by hand if needed.
monarch theme apply
```

### Keybindings

Edit `~/.config/niri/user.kdl`. Niri uses a `binds { … }` block with KDL syntax:

```kdl
binds {
    Mod+Return hotkey-overlay-title="Terminal" { spawn "alacritty"; }
    Mod+Q      hotkey-overlay-title="Close window" { close-window; }
    Mod+L      hotkey-overlay-title="Lock screen" { spawn "monarch-system-lock"; }
}
```

View current bindings: `monarch menu keybindings --print`

**IMPORTANT: Niri does not have an explicit `unbind`.** To override a default binding, simply
redefine the same chord in your `user.kdl` — the last definition wins because the user file is
appended last by `monarch-refresh-niri`.

### Display/Monitors

Edit `~/.config/niri/user.kdl`:

```kdl
output "eDP-1" {
    mode "2880x1920@120.000"
    scale 2
    position x=0 y=0
}

output "DP-1" {
    mode "3840x2160@60.000"
    scale 1.5
    position x=1440 y=0
}
```

List outputs: `niri msg outputs` (or `niri msg --json outputs` for JSON).

### Window Rules

Window rules live in the same `~/.config/niri/user.kdl` as everything else. Niri syntax:

```kdl
window-rule {
    match app-id=r#"^org\.telegram\.desktop$"#
    open-floating true
    default-column-width { fixed 600; }
}
```

Refer to the Niri configuration reference at <https://yalter.github.io/niri/Configuration%3A-Window-Rules.html> for the full grammar and field list before writing rules.

### Fonts

```bash
monarch font list               # Available fonts
monarch font current            # Current font
monarch font set <name>         # Change font
```

### System

```bash
monarch update                  # Full system update
monarch version                 # Show Monarch version
monarch debug --no-sudo --print # Debug info (ALWAYS use these flags)
monarch system lock             # Lock screen
monarch system shutdown         # Shutdown
monarch system reboot           # Reboot
```

**IMPORTANT:** Always run `monarch debug` with `--no-sudo --print` flags to avoid interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
monarch debug --no-sudo --print

# Upload logs for support
monarch upload log

# Reset specific config to defaults
monarch refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `monarch refresh config noctalia/settings.json` will refresh ~/.config/noctalia/settings.json
monarch refresh config <config-file>

# Full reinstall of configs (nuclear option)
monarch reinstall
```

## Decision Framework

When user requests system changes:

1. **Is it a stock monarch command?** Use it directly via `monarch <group> <action>`
2. **Is it a config edit?** Edit in `~/.config/`, never `~/.local/share/monarch/`
3. **Is it a theme / color change?** Use Noctalia (scheme picker, dark/light toggle, or edit `colorschemes/Monarch/Monarch.json`)
4. **Is it automation?** Use hooks in `~/.config/monarch/hooks/`
5. **Is it a package install?** Use `monarch pkg add` (or `monarch pkg aur add` for AUR-only packages)
6. **Unsure if command exists?** Run `monarch commands` or `monarch <group> --help`

### Reminder Requests

When the user asks to set a reminder, use `monarch reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
monarch reminder 15 "Pickup Jack"
monarch reminder 60 "Check laundry"
monarch reminder show
monarch reminder clear
```

## Out of Scope

This skill intentionally does not cover Monarch source development. Do not use this skill for:
- Editing files in `~/.local/share/monarch/` (`bin/`, `config/`, `default/`, `themes/`, `migrations/`, etc.)
- Creating or editing migrations
- Running `monarch dev ...` commands

## Example Requests

- "Change my theme to catppuccin" -> Open the Noctalia scheme picker (Mod+Shift+Comma) or `qs -c noctalia-shell ipc call colorScheme set Catppuccin`
- "Switch to light mode" -> `qs -c noctalia-shell ipc call darkMode toggle` (or the control center toggle)
- "Add a keybinding for Super+E to open file manager" -> Add the bind in `~/.config/niri/user.kdl` (a later redefinition overrides any default with the same chord), then `monarch refresh niri`
- "Configure my external monitor" -> Edit the `output` block in `~/.config/niri/user.kdl`
- "Make the window gaps smaller" -> Add a `layout { gaps … }` block in `~/.config/niri/user.kdl`
- "Set up night light to turn on at sunset" -> `monarch toggle nightlight` for a manual on/off, or configure a schedule in Noctalia: set `nightLight.autoSchedule` (or `manualSunset`/`manualSunrise`) and `nightLight.nightTemp` under `~/.config/noctalia/settings.json`
- "Set a reminder to pickup jack in 15 minutes" -> `monarch reminder 15 "Pickup Jack"`
- "Show my reminders" -> `monarch reminder show`
- "Clear all reminders" -> `monarch reminder clear`
- "Customize the Monarch palette" -> Edit `~/.config/noctalia/colorschemes/Monarch/Monarch.json` (`dark`/`light` blocks), then re-select Monarch in the Noctalia picker
- "Re-apply theming to my wallpaper / keyboard RGB / Plymouth" -> `monarch theme apply` (Noctalia runs this automatically on a scheme change)
- "Reset Noctalia to defaults" -> `monarch refresh noctalia`
- "Move the bar to the right edge" -> Edit `bar.position` in `~/.config/noctalia/settings.json` or use the Settings panel (Mod+Shift+Comma)
