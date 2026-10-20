# Monarch bar indicators

Small widgets for active desktop features and pending work. The update widget
uses the existing `monarch-update-available --all --json` command; it does not
implement its own package or repository checks.

## Update indicator

- Hidden without confirmed Internet connectivity or after a complete check
  confirms that no updates are available.
- Displays the total number of verified upgrades beside the update icon.
- Uses one theme role for both the icon text and count, with priority:
  **Monarch → repositories → AUR** (`primary`, `secondary`, `tertiary`). These are
  theme-aware categories, not security-severity ratings. The Monarch category
  includes `monarch` and `monarch-settings` from the repositories.
- On hover, shows the total, category counts, and installed → available versions.
  Packages are ordered by category and name. At most twelve package rows are
  shown, followed by the remaining count, so a large upgrade fits in a tooltip.
- A failed AUR check retains verified repository updates, displays a lower-bound
  count (`≥N`), and marks AUR availability as unknown rather than zero.
- A failed or malformed online check shows a warning triangle in the neutral
  `on_surface_variant` theme role. Previously known updates remain in the
  tooltip but are explicitly labelled stale.
- Left-click opens the interactive system updater in a floating terminal.
- Tooltips follow Monarch's interface language, independently of Noctalia's.

The stream checks every six hours after a confirmed up-to-date result and every
ten minutes while updates are pending or a check is failing. Offline connectivity
is rechecked every minute without querying repositories. Duplicate payloads
are not emitted. Passive checks never install packages or request sudo.

## Validation

```bash
bash test/shell.d/update-indicator-test.sh
bash test/shell.d/update-available-test.sh
noctalia plugins lint default/noctalia/plugins/monarch-indicators
```

Tests cover category priority, counts, versions, partial coverage, bounded
tooltips, malformed results, stale-state recovery, retry cadence, and English
and French output. Visual verification must also check the widget and tooltip
in a running Noctalia session.
