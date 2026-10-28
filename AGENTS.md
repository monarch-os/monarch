# Security

Security is a requirement of every contribution, not a final optional check. Simplicity must never weaken a security boundary.

- Use least privilege; elevate only the operation that needs it. Keep user/session work outside privileged code.
- Validate external input at trust boundaries: arguments, paths, downloaded content and user-controlled files. Quote shell expansions outside `[[ ]]` and arithmetic contexts; use arrays for commands rather than interpolating data into shell code.
- Privileged code must not source or execute user-writable code, trust a user-controlled executable search path, or accept an unchecked runtime root. Keep downloaded data separate from executable hooks; verify artifacts using the project's trusted signature or checksum mechanism before executing or installing them.
- Stop before destructive cleanup or an incomplete security transition if validation or prerequisites fail. Never silently disable verification, authentication or permission checks to make a feature work.
- Keep secrets out of source, fixtures, examples and logs. Redact sensitive diagnostics.
- Create temporary files and directories securely with `mktemp`; use restrictive permissions for sensitive data and clean up owned temporary resources on exit. Privileged file operations must prevent symlink redirection and check/use races in user-writable locations.
- Propagate important failures and preserve actionable diagnostics without exposing secrets. Do not silently discard errors or report success after a required operation fails.
- Changes to privileges, permissions, downloads or dynamic command execution must explain the trust boundary and failure behavior in the contribution, and include focused behavioral coverage for changed security logic.

# Simplicity (KISS)

- Choose the simplest solution that meets the actual need and its security requirements. Prefer explicit control flow and a full `if`/`else` over relying on an early `exec` or `exit` to imply the other branch.
- Reuse existing helpers. Add an abstraction only when it makes existing code easier to understand; avoid speculative frameworks, options and fallback paths.
- Keep changes focused. Separate unrelated refactoring and avoid defensive checks for dependencies guaranteed by the runtime.
- Long-running services, watchers and plugins react to events. Poll only when no change signal exists, and document why.
- Measure before optimizing: identify the actual bottleneck and compare representative before/after results. Prefer a simpler implementation unless the measured gain justifies added complexity.
- Bound external calls with appropriate timeouts and retries; limit concurrency and the volume of untrusted data processed. A timeout or exhausted limit must produce an explicit, handled failure.
- Add caching only for a measured benefit, with explicit invalidation rules and bounded storage. Preserve correctness when the underlying state changes.
- Comments explain a non-obvious reason or constraint, in one or two lines. Do not narrate code, repeat an error message, or add section banners.

# Documentation and Task Guides

- **User documentation lives in [GitBook](https://docs.monarchlinux.com/)**: installation, usage, configuration and troubleshooting.
- **Technical documentation lives in [`docs/`](docs/README.md)**: architecture, interfaces, implementation contracts and product decisions.
- **Contribution procedures live in `agents/skills/`**. These are distinct from `default/agents/skills/`, which contains skills shipped to users.
- `AGENTS.md` holds common rules and links. Update the relevant documentation when behavior changes; link to its canonical home rather than maintaining duplicate instructions. If a GitBook update cannot be completed, state the outstanding update explicitly.
- Read the matching [development guide](agents/skills/development.md) before changing commands, installation, configuration, menus, theming or upstream integrations, and the [testing guide](agents/skills/testing.md) before validation.

# Style

- Two spaces for indentation, no tabs.
- Use Bash 5 `[[ ]]` for string/file tests and `(( ))` for numeric tests, not numeric operators inside `[[ ]]`.
- In `[[ ]]`, leave variables unquoted and quote string literals when comparing values: `[[ $branch == "dev" ]]`.
- Quote paths containing spaces: `"$APP_DIR/Disk Usage.desktop"`, not backslash-escaped spaces.
- Use `#!/bin/bash`, never `#!/usr/bin/env bash`. Sourced scripts under `install/` intentionally omit shebangs.
- A security-sensitive entrypoint may use exactly `#!/bin/bash -p` only to suppress `BASH_ENV` and exported-function injection before its first command. Explain the boundary and test that an ordinary Bash launch with a decoy `-p` argument is rejected.
- Write Markdown paragraphs and list items without hard wrapping at 80 columns; break at structural boundaries.

# Git and Worktrees

- Make every repository modification in a dedicated worktree under that repository's `.worktrees/<name>/`, never in its primary checkout. A `monarch-pkgs` worktree belongs under `monarch-pkgs/.worktrees/`, not here or beside the repositories.
- Keep commits atomic, with succinct English messages describing one coherent change.
- After the user confirms a merge, offer to remove the worktree and local branch; wait for confirmation before removing them.

# Monarch Invariants

- Preserve [product decisions](docs/product-decisions.md): Niri is the compositor; Noctalia v5 is the native desktop shell and owns theming; plugins are Luau.
- All commands start with `monarch-`. `GROUP_DESCRIPTIONS` in `bin/monarch` is the command group source of truth; see the [CLI reference](docs/development.md#command-naming).
- Use idempotent reconciliation for upgrades. Do not add timestamped migrations; see [reconciliation](docs/development.md#reconciliation).
- Verify visual changes in the running UI and inspect a screenshot taken with `monarch capture screenshot fullscreen save`.
