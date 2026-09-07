# Webapps

Create a webapp launcher with `monarch webapp install`, or provide its name,
HTTP(S) URL and icon directly:

```bash
monarch webapp install 'Portal' 'https://example.com' '/path/to/portal.png'
```

The icon can be an image URL, a local image file or an installed icon name.
Local images are copied and normalized into a separate launcher icon. The
original image remains in place, including when the webapp is removed.

With an empty icon argument, Monarch tries icons advertised by the site, then
the standard Apple touch icon and Google's favicon service. Discovery has a
30-second budget, including decoding: site candidates cannot consume the last
ten seconds, and the Apple attempt leaves five seconds for Google. A timeout
can still prevent finding an icon, but slow site candidates cannot exhaust the
fallbacks' reserved time.

An optional fourth argument supplies a custom Desktop Entry `Exec` command;
an optional fifth argument supplies MIME types. New launchers carry
`X-Monarch-WebApp=true`, including those with custom commands, so Monarch can
recognize them for replacement and removal.

## Existing launchers

Monarch recognizes regular `.desktop` files with `Type=Application` and a
non-empty `Exec` when either:

- They carry `X-Monarch-WebApp=true`.
- Their `Exec` starts with the exact executable `monarch-launch-webapp` or
  `monarch-webapp-handler-zoom`, optionally double-quoted and followed by
  arguments. Merely mentioning either command in an argument does not count.

The second rule keeps older standard webapps and Zoom handlers manageable
without a marker. Reinstalling one under the same name creates a marked
launcher. Old source icons are preserved.

Older launchers using an arbitrary custom `Exec` without the marker cannot be
distinguished from launchers created by the user. Monarch leaves them in place,
excludes them from webapp removal, and refuses to overwrite them. They can
still be launched normally. Updates do not automatically migrate these files
or add a marker.

To create a managed replacement, keep the old launcher and install under a
different name. Reuse its URL, source icon and custom command, for example:

```bash
monarch webapp install 'Portal (Monarch)' 'https://example.com' \
  '/path/to/portal.png' 'firefox --new-window https://example.com'
```

The new launcher is managed even with a custom command. The old launcher and
the source icon remain unchanged, so you can verify the replacement before
deciding what to do with the old file.
