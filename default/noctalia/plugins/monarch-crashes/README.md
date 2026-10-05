# Crashes

Open **monarch-menu → System → Crashes** (`Win + Alt + Space`), or run:

```bash
monarch crash history
```

The panel shows the 100 most recent crashes recorded by `systemd-coredump` for
the current user, newest first. The details view shows the signal and core dump
availability. Preparing a report displays its contents; exporting it saves the
exact preview to a private text file under
`${XDG_STATE_HOME:-~/.local/state}/monarch/crashes/reports/`.

When collection is configured and available, sending opens a confirmation screen
showing the destination and retention period. Confirming sends the report you
reviewed. After receipt, you can copy its unique link into a GitHub issue. The
link remains available when you reopen the panel; viewing it requires a
maintainer account authenticated through Cloudflare Access.

The report contains the application, UTC date, signal, versions and backtrace
recorded in the journal. System versions reflect the time the report was
prepared. The package version comes from the crash metadata when available,
otherwise from the currently installed package. The backtrace is limited to
120 lines, and common private paths are redacted, including paths with spaces
or parentheses. Review the contents before sharing.

The memory dump, environment, command line and general system logs are excluded.
Reports are sent only after confirmation. You can open an exported report in a
local application before attaching it to an issue.

An event can remain in the journal after its core dump has been deleted. The
panel still displays it; an absent backtrace does not mean that no crash occurred.
Script exceptions without core dumps, normal exits and processes killed due to
memory exhaustion are outside the scope of this history.

Disable notifications through **Actions → Toggle → Crash Capture** or
`monarch toggle crash-capture`. This setting controls notifications; systemd
continues to retain crash events. With no AI agent configured, a notification
opens the history. With an agent configured, it offers the existing analysis
workflow.

## Command line

```bash
monarch crash history list
monarch crash history list --json
monarch crash history report '<id>'
monarch crash history report '<id>' --json
monarch crash history export '<id>'
```

The identifier combines the boot ID, PID and crash timestamp to distinguish
events when the system reuses a PID. `list --json` returns `crashes`, `limit` and
`hasMore`; `export` returns the file path as JSON. Journal access failures are
reported as errors instead of appearing as an empty history.

The panel uses `export '<id>' --stdin` to preserve the previewed text even if the
journal rotates between preparation and export. This option accepts a text
report of up to 64 KiB. Without it, `export` prepares a new report.

The collection service and its dashboard are maintained separately from the
client packaged with the OS.

## Voluntary submission

The client stores a frozen, private preview before sending. It also works
independently of the panel:

```bash
monarch crash submit status
monarch crash submit prepare '<id>' | jq -r .text
monarch crash submit send '<id>' --confirm 'https://crashes.monarchlinux.com'
monarch crash submit copy '<id>'
```

`prepare` preserves the same report when reopened. Sending reuses that snapshot.
The response contains an `MCR-…` reference and a URL; retries after a network
failure use the same key to avoid duplicates. After receipt, the client retains
the reference and link and skips further uploads for that crash. `copy` places
the link on the clipboard without a network request.

The destination passed after `--confirm` must match the current configuration.
The panel passes the destination it displays, and the client rejects the upload
if it has changed since the availability check. On the command line, `--confirm`
without a destination confirms sending to the currently configured destination.

Remote collection remains disabled in the defaults until the Cloudflare service
has been deployed and tested. Configure its URL in
`~/.config/monarch/crash-reporting.json`:

```json
{"endpoint":"https://crashes.monarchlinux.com"}
```

The client requires HTTPS, rejects redirects and sends reports without
Cloudflare tokens. Reports and receipts are stored locally under
`${XDG_STATE_HOME:-~/.local/state}/monarch/crashes/submissions/`, with the same
private permissions as exports. The service advertises its remote retention
period; local files remain stored separately.

After a remote report is purged, its link indicates that it is unavailable or
expired. A link in a GitHub issue does not extend its retention period.

For local testing only, `MONARCH_CRASH_ENDPOINT=http://127.0.0.1:8787` together
with `MONARCH_CRASH_ALLOW_LOCAL=1` enables the local Worker.
