![](assets/logo.png)

# Monarch

Monarch turns a fresh [CachyOS](https://cachyos.org) installation into a fully-configured, beautiful, and modern desktop — purpose-built as a **cybersecurity platform**, inspired by [SkillArch](https://github.com/laluka/SkillArch), with tools and aliases preinstalled.

It runs its own desktop stack:

- **Compositor**: [Niri](https://github.com/YaLTeR/niri), a scrollable-tiling Wayland compositor, for a stable and ergonomic experience.
- **Desktop shell**: [Noctalia](https://github.com/noctalia-dev/noctalia), a native Wayland shell providing the bar, launcher, notifications, control center, lock screen, OSDs, wallpaper, and theming.

Monarch is a fork of [Omarchy](https://omarchy.org). The `monarch` CLI and the install scripts descend from it, and a good number of commands are still Omarchy's unchanged but for the name. The stack has since diverged — CachyOS rather than Arch, Niri rather than Hyprland, Noctalia rather than waybar and its neighbours — but the lineage is Omarchy's, and so is the licence.

## Application theme templates

Noctalia themes applications from its built-in and community catalogs. For an
application absent from those catalogs, copy
`~/.config/noctalia/user-templates.toml.example` to another `.toml` file and
define a native `[theme.templates.user.<id>]` entry. The example remains inert
until copied and enabled. Template tokens and filters are documented in
[Noctalia's template reference](https://docs.noctalia.dev/noctalia/theming/templates/).

User templates follow palette changes automatically. If one replaces a
catalog template, redefine `builtin_ids` or `community_ids` in the same overlay
without that template's id: reusing its id does not disable the catalog entry.

Static template and output paths keep the declaration data-only. Noctalia also
supports hooks and dynamic output commands, but those execute as the desktop
user on every applicable theme change and must be treated as trusted local
code. Installable Monarch theme bundles never include them.

## License

Monarch is released under the [MIT License](https://opensource.org/licenses/MIT), inherited from Omarchy.
