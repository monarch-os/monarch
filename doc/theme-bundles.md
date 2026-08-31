# Installable themes

A Monarch theme is a Git repository containing data only. Install one with:

```bash
monarch theme install https://github.com/example/aurora-monarch-theme.git
```

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

Installed themes retain their Git origin and revision. Use `monarch theme
update` to fetch a newer revision and `monarch theme remove` to uninstall one.
Both are also available in the Monarch menu. Updates replace the managed bundle
atomically. Wallpapers imported through Monarch remain in the user's background
directory and survive both updates and removal.
