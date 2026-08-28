# Test suite

`test/suite.tsv` is the inventory and ownership record for every executable
test. Each row names the feature, risk and environment needed by that test.
Adding or removing a `*-test.sh` file without updating the manifest makes the
runner fail.

The supported entry points are:

- `test/run focused test/monarch-menu-test.sh` for one or more named tests;
- `test/run integration` for every deterministic, repository-local test;
- `test/run full` for integration tests plus network and workspace checks.

`integration` is the required deterministic pull-request suite. CI keeps the
network availability check in its own job so an external outage is distinct
from a product regression. `full` additionally contacts the configured Pacman
and PyPI repositories. `TEST_JOBS` controls file-level parallelism and defaults
to four. Tests own their temporary directories and must not depend on execution
order or another test's fixtures.

## Q18 baseline and decisions

The initial inventory contained 50 executable tests. The GitHub workflow ran 10
unique files, ran the Niri socket test twice, and repeated the CLI route check
already asserted by `monarch-cli-test.sh`. A serial local inventory took 164 s:
45 files passed, two workspace-dependent files could not locate `monarch-pkgs`
from a worktree, the network check failed without network access, the Niri
socket fixture was blocked by the sandbox, and the menu test timed out at 90 s.

Q18 keeps the meaningful behavior from all 50 original files in 49 tests. The
milestone-named Q15 test was folded into its owning menu and Noctalia suites;
package-recipe assertions moved to `monarch-pkgs`. Repository and PyPI
availability stays in the `network` tier, with the other 48 tests in the
deterministic integration suite. Menu declaration tests now parse one
guard-free tree snapshot; they no longer repeatedly execute unrelated runtime
guards. The obsolete Hyprland/Quickshell helpers had no callers and were
removed. The CI duplicate and redundant standalone route checks were replaced
by the integration entry point. Final runtime measurements are recorded after
the rationalized suite passes. With four workers, the final 48-test integration
suite completes in 25.7 s and the 49-test full suite in 28.4 s on the Q18
development machine, both with zero failures.

The menu test still has a small set of structural Luau assertions for behavior
that cannot be exercised without loading the Noctalia plugin host: viewport
capacity, pointer/keyboard import wiring, category search, exact-match ranking
and grouped results. They are intentionally isolated in that test and should be
replaced by plugin-level behavioral tests when Noctalia provides a headless test
harness. The Satty absence check remains a deliberate regression contract for
Monarch's Tensaku screenshot workflow.
