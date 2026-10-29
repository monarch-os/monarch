# Testing contributions

Use the repository's actual runners and environment requirements in [test/README.md](../../test/README.md). Do not copy upstream runner names or test paths without checking that they exist here.

## Choose the scope

- Start with the tests owning the changed behavior: `test/run focused test/monarch-menu-test.sh` is an example. Consult `test/suite.tsv` for ownership and environment requirements.
- `test/run integration` is the required deterministic pull-request suite. Run it once at the end when preparing a code PR, and after changes to shared helpers or test infrastructure. `test/run full` additionally exercises network and workspace checks; use it when those integrations are affected.
- For CLI metadata/routes or an upstream sync, run `bash test/monarch-cli-test.sh` and `bin/monarch commands --check`.
- Documentation-only changes need link/path checks and `git diff --check`, not a new behavioral test or a desktop session.
- Graphical acceptance tests belong in a disposable VM through `monarch-iso-test`; follow `test/README.md`. Visual changes also require inspecting the running UI and a screenshot.

## Preserve evidence

- Save complete output before inspecting it: `test/run focused test/monarch-menu-test.sh > /tmp/opencode/monarch-menu-test.log 2>&1`. Ensure the log directory exists. Check the command's exit status, then read its log; never pipe a running test into `head`, `tail` or `grep` and lose evidence.
- Repeat a test only after a relevant change or to investigate a specific unresolved failure, not to reconfirm a pass or retrieve discarded output.
- For an apparently unrelated failure, run that test once on the base revision in a separate worktree. Report a reproduced pre-existing failure separately; preserve unrelated user changes.
- Tests that read a live session can be affected by desktop activity. Report environmental interference rather than looping until green.

## Add meaningful coverage

- Name the regression a new test catches before writing it. For a logic bug, add the focused test that fails on the base revision for that reason and passes with the fix.
- Exercise real behavior: parsing, routing, permission boundaries, failure handling or a relevant edge case. Mocks isolate dependencies; they must not implement the behavior being tested.
- Do not add tests that grep for the line just added, restate constants, snapshot unrelated output or assert exact incidental file counts. Small declarative changes usually need no new test.
- Extend the area's existing test file where possible and follow its style. If adding or removing an executable test, update `test/suite.tsv`.
- Keep coverage proportional, including negative cases for changed security-sensitive logic. Prefer testable helper logic over testing one-off setup text.
