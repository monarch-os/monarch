# Monarch

[![Documentation](https://img.shields.io/badge/Documentation-Read_the_docs-7e33ff?style=flat-square)](https://docs.monarchlinux.com/)
[![CI](https://img.shields.io/github/actions/workflow/status/monarch-os/monarch/ci.yml?branch=dev&label=CI&style=flat-square)](https://github.com/monarch-os/monarch/actions/workflows/ci.yml?query=branch%3Adev)

Monarch turns a fresh [CachyOS](https://cachyos.org) installation into a fully-configured, beautiful, and modern desktop — purpose-built as a **cybersecurity platform**, inspired by [SkillArch](https://github.com/laluka/SkillArch), with tools and aliases preinstalled.

Read the [documentation](https://docs.monarchlinux.com/) to install Monarch and get started.

Prefer a bootable installer? [Download the latest nightly ISO](https://iso.monarchlinux.com/monarch-nightly.iso).

![Monarch desktop in use, with terminal workflows, Niri navigation, and live theme switching](assets/demo.gif)

*[Static preview](assets/demo.png).*

It runs its own desktop stack:

- **Compositor**: [Niri](https://github.com/YaLTeR/niri), a scrollable-tiling Wayland compositor, for a stable and ergonomic experience.
- **Desktop shell**: [Noctalia](https://github.com/noctalia-dev/noctalia), a native Wayland shell providing the bar, launcher, notifications, control center, lock screen, OSDs, wallpaper, and theming.

Monarch is an independently maintained **hard fork** of [Omarchy](https://omarchy.org). The `monarch` CLI and the install scripts descend from it, and a good number of commands are still Omarchy's unchanged but for the name. The stack has since diverged — CachyOS rather than Arch, Niri rather than Hyprland, Noctalia rather than waybar and its neighbours — but the lineage is Omarchy's, and so is the licence.

## The true monarchs

Monarch is, first and foremost, an assembly of projects built and maintained by others. Its role is to bring them together into a cohesive desktop and cybersecurity environment — not to take credit for their work. The people and communities behind those projects are the true sovereigns:

- [Noctalia](https://github.com/noctalia-dev/noctalia) — the desktop shell that brings the interface to life, from the bar and launcher to notifications and theming.
- [Niri](https://github.com/YaLTeR/niri) — the scrollable-tiling Wayland compositor at the heart of the desktop.
- [SkillArch](https://github.com/laluka/SkillArch) — the inspiration for Monarch's cybersecurity workflows, tools, and shell helpers.
- [Exegol](https://github.com/ThePorgs/Exegol) — the source of inspiration for several of Monarch's cybersecurity aliases.
- [Omarchy](https://omarchy.org) — the original foundation of Monarch's installer, CLI, and many everyday commands.
- [CachyOS](https://cachyos.org) and [Arch Linux](https://archlinux.org) — the distribution foundations and package ecosystem that make it all possible.

And to the many other upstream projects, maintainers, and contributors whose work makes this environment possible: thank you. The crown belongs to you.

## Contributing

Contributions are welcome — bug reports, ideas, documentation, translations, and code all help make Monarch better.

- Check the [existing issues](https://github.com/monarch-os/monarch/issues) before reporting a bug or suggesting a feature. Include your setup, steps to reproduce, and relevant logs when reporting a problem.
- For larger changes, open an issue first so we can discuss the approach before you invest time in an implementation.
- Keep pull requests focused, follow the repository's [development guidance](AGENTS.md), and describe what changed and how you tested it. Include screenshots for visual changes.
- When a problem belongs to an upstream project, help improve it there too — Monarch benefits when its foundations get better.

## License

Monarch is released under the [MIT License](https://opensource.org/licenses/MIT), inherited from Omarchy.
