# Theme bundle specification

User instructions for installing, updating and removing themes live in the
[Themes guide](https://docs.monarchlinux.com/basics/themes). This document
defines the bundle contract implemented by Monarch.

The repository must contain `monarch-theme.json`:

```json
{
  "schema": 1,
  "id": "aurora",
  "name": "Aurora",
  "palette": "palette.json",
  "backgrounds": "backgrounds",
  "preview": "preview.png"
}
```

`id` is the lowercase kebab-case form of `name`. The palette uses Noctalia's
custom palette format with both `dark` and `light` variants. `backgrounds` is a
flat directory of JPEG, PNG, GIF, BMP or WebP images. `preview` is optional.

The repository may also contain README, LICENSE and CHANGELOG files. Symbolic
links, executable files, nested background directories and all other content
are rejected. Theme repositories cannot install scripts or application
configuration.

Installed themes retain their Git origin and revision. Updates replace the managed bundle
atomically. Wallpapers imported through Monarch remain in the user's background
directory and survive both updates and removal.
