# Versioning and monthly patch notes

Monarch updates continuously. CalVer identifies its desktop runtime, not the
complete set of installed Arch packages or its installation schema.

Tags use `vYYYY.MM.N`: `v2026.10.0`, `v2026.10.1`, and so on. After all CI jobs
pass on a push to `dev`, the version job tags that exact tested commit. Protect
`dev` against direct pushes if every version must correspond to a PR merge.
Pull requests, failed CI runs and pushes to `main` do not allocate versions.
Rerunning a tagged revision reuses its tag. Tag allocation is serialized with
`queue: max`, so waiting jobs are not replaced by newer merges; numbers follow
allocation order, not necessarily commit or CI start order.

The first automatic tag bootstraps `2026.10.0`. Subsequent automatic tags increment
the last component, even across calendar month boundaries. No bump commits are
created, and intermediate tags do not create GitHub releases.

## Publish a monthly milestone

Run the **CI** workflow manually on **dev**, supplying:

- `month`: the new milestone, such as `2026.11`;
- `notes`: reviewed Markdown patch notes, covering features, fixes, required
  actions and known issues since the previous monthly milestone.

After the same tests pass, the job creates `v2026.11.0` and a GitHub release
named **Monarch 2026.11**. The month must advance the active milestone, and the
tested revision must contain the latest tagged revision. A retry can finish
publication after the tag was pushed, without allocating another version.
To publish the initial `2026.10` notes, dispatch on the commit tagged
`v2026.10.0`. An existing monthly tag can be published on retry even if newer
intermediate tags have since been allocated.

For an existing monthly tag:

```bash
gh workflow run ci.yml --ref v2026.10.0 -f month=2026.10 -f notes='Reviewed patch notes'
```

Dispatch on a tag is reserved for publishing its existing milestone, not creating
a new one.

Workflow dispatch requires this workflow to be present on the repository's
default branch. GitHub Actions must be permitted to write repository contents;
tag rules must allow the workflow token to create these tags.
The write-enabled version job pins checkout to a full immutable commit SHA;
review dependency updates before changing that pin.

Patch notes describe changes actually delivered through the package repository,
not merely merged changes. Check package availability before monthly publication.
Urgent security notices and breaking changes are announced immediately.

## Runtime identity

The `monarch` package generates `/usr/share/monarch/version` from its package
version and records the source commit in `/usr/share/monarch/revision`.
`monarch version` prints the version; `monarch version --commit` prints the commit.
Untagged builds retain a Git distance and hash suffix. The source `version` file
is a legacy fallback for source archives, not a monthly bump target.
Builds use the numerically greatest reachable version tag, so a delayed CI job
tagging an older ancestor cannot make a descendant build regress in version.
Only canonical `vYYYY.MM.N` tags qualify; legacy Omarchy tags, prereleases and
malformed CalVer tags are ignored.

Tags do not publish packages. The package builder remains responsible for build,
signing and delivery. Merge the corresponding `monarch-pkgs` packaging change
before relying on generated runtime identity.

The bar indicator checks published package upgrades with `checkupdates`, using
an isolated temporary database and no privilege elevation. Only an upgrade for
the installed `monarch` package raises its badge, not a new Git tag or unrelated
Arch updates. The check returns 0 for an available upgrade, 1 for no Monarch
upgrade, and 2 for a failed check. Repository checks have a two-minute deadline
with five seconds of termination grace.
After a failure the indicator retains its last state and retries in ten minutes,
rather than incorrectly clearing an available-update badge.

`monarch-update-available` is the shared availability command:

- No options: check only the `monarch` package, preserving the bar's behaviour.
- `--all`: include every repository package and AUR upgrades. AUR is only queried
  when foreign packages are installed; its check has the same two-minute deadline.
- `--json`: change the output format without changing the selected scope.
- Exit status is always 0 for available upgrades, 1 for no upgrades, and 2 for a
  failed check, including with `--json`.

Successful JSON includes `status`, `scope`, `count`, `packages`, `repositories`,
`aur` and `counts`. Each package has `name`, `category`, `installed` and `available`
versions. Categories are `monarch` (the `monarch` and `monarch-settings` repository
packages), `repo` (other repository packages) and `aur`. The disjoint `counts`
object uses these three categories; `repositories` includes both `monarch` and
`repo`. The default scope still selects only the exact `monarch` package, not the
whole category. Failures return `status: "error"`, `count: null` and a stable
`reason`, never a false zero-update result. The format is independent of language.

The first-steps guide and `monarch update` use `--all --json`. The updater checks
before confirmation and maintenance, exits successfully without changes when
current, and stops on a failed check. `-y` skips confirmation, not verification.
An explicit `--branch` switch bypasses this current-branch availability gate.
Declining an available update returns 130 so the guide does not record a success.

Installation schema versions remain independent and only change for architectural
upgrade transitions.
