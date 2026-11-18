---
name: prune-tests
description: Review and prune tests that do not protect intended behavior. Use when asked to prune, audit, simplify, or clean up a test suite.
disable-model-invocation: true
---

# Prune tests

Apply this procedure to the requested repository or path. Follow its contribution, security, worktree, and testing instructions.

## Review

For each test, identify the intended behavior it protects and a concrete regression that would make it fail. Look for:

- Tests that assert removed source, files, or features remain absent without protecting current behavior.
- Tests that cannot detect a defect, including tests of a mock's own behavior or expectations derived from the implementation under test.
- Tests coupled to incidental implementation details, such as exact source lines, private helpers, or call order.
- Redundant tests that cover the same regression at the same boundary.

Distinguish an assertion about removed code from a current behavior that removes something: for example, an upgrade must actually clean up an obsolete configuration. Keep meaningful negative and security-boundary cases. Tests at different boundaries, such as unit and integration, may detect different failures even when they cover the same feature.

## Act

- Remove tests that protect no current behavior; rewrite brittle tests when they also protect useful behavior.
- Before removing a duplicate, compare its failure modes and preserve any unique coverage.
- Inspect all references and uses before removing production code or test helpers. Do not remove production code solely because a test was deleted.
- Respect the requested scope. If asked only for a review, report candidates without editing. Preserve unrelated changes.
- Update test runners and references when removing or moving test files.

## Validate and report

Run the relevant remaining tests using the repository's documented runners. Where practical, check that a rewritten test fails for the intended regression, then passes with the correct implementation. Do not launch destructive or graphical integration environments without the required permission.

Report what was removed or rewritten, what behavior remains covered, and any coverage lost or unverified. For review-only work, cite the candidates and distinguish confirmed problems from hypotheses.
