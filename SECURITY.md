# Security Policy

## System and Scope

Monarch is an Arch-based desktop operating system. This repository owns the
packaged runtime under `/usr/share/monarch`, its `/usr/bin/monarch*` entry
points, system and user defaults, installation stages, and reconciliation
logic.

Security work may cross repository boundaries:

| Surface | Owning repository |
|---|---|
| Runtime commands, defaults, reconciliation | `monarch` |
| PKGBUILDs, install hooks, package contents | `monarch-pkgs` |
| Package build, signing, promotion, pruning, R2 publication | `monarch-pkgs-builder` |
| Live installer, partitioning, chroot orchestration, first boot | `monarch-iso` |
| Repository storage, signing infrastructure, DNS | `monarch-iac` and deployment infrastructure |

Report a finding in the repository where the unsafe behavior originates.
Needing a coordinated fix in another repository does not make a finding out of
scope.

## Threat Model and Trust Boundaries

Treat the desktop user, processes in their session, home-directory contents,
environment variables, command arguments, downloaded metadata, network
responses, removable media, and legacy installation state as untrusted.

Root-owned package contents, repository signing keys, and an administrator who
deliberately authenticates a privileged operation are trusted. A compromised
dependency or build service remains relevant when Monarch's packaging or
configuration turns it into a boundary crossing.

Important boundaries include user to root, session to system service, network
to local execution, package source to installed system, and one user's data to
another user's account.

## Security Invariants

- Packaged executables and privileged configuration must resolve only through
  root-owned paths that are not writable by unprivileged users.
- Code crossing a sudo, polkit, system-service, installer, or reconciliation
  boundary must validate inputs again and use a trusted command path.
- Root-owned publication must reject unsafe symlinks and writable parents,
  preserve unrelated administrator state, and replace complete validated
  outputs atomically.
- Sudoers and polkit grants must authorize fixed operations and constrained
  arguments. Broad command, path, environment, Docker, or input-device access
  must never be granted by default.
- Network services must remain unavailable until their authentication and
  firewall controls are ready. SSH must prove a usable key and effective
  key-only policy before exposure.
- System updates must retain package-signature enforcement, serialization,
  preflight checks, and fail-closed reconciliation with retryable state.
- Passwords, authentication tokens, private keys, and recovery material must
  not leak through process arguments, inherited environments, logs, or
  world-readable files.
- Destructive operations must use an explicit, revalidated target and must not
  infer ownership from a display name or user-controlled path alone.

## Reportable Findings and Severity Context

A security finding requires a realistic violation of a meaningful boundary,
not only code that could be more defensive.

Examples include unprivileged code execution as root, authentication bypass,
credential disclosure, arbitrary privileged file writes, unsafe package or
update execution, remotely reachable command execution, or destructive access
outside the user's selected target.

Root execution, remote unauthenticated access, signing-key compromise, and
credential theft normally carry the highest severity. Findings requiring an
explicit local opt-in, administrator authentication, or substantial prior
privilege should be calibrated to those prerequisites.

## Out of Scope and Accepted Product Boundaries

- A vulnerability entirely inside an unmodified third-party component is
  normally reported upstream unless Monarch exposes or amplifies it.
- General hardening opportunities without a reachable boundary crossing are
  improvements rather than vulnerabilities.
- Docker-group access and raw input access are intentionally privileged
  capabilities after the user explicitly enables their warned opt-in.
  Bypassing that opt-in remains reportable.
- An attacker who already controls root, the package-signing infrastructure, or
  the machine below the trusted boot boundary is outside this repository's
  local privilege model.

## Known Limitations and Compensating Controls

User-authored Noctalia template hooks and dynamic output commands are trusted
local code, not a sandbox. Installable Monarch theme bundles remain data-only.

Optional AUR software has its own upstream and packaging trust boundary.
Monarch's signed repository and package tooling must still prevent unintended
packages or unsigned metadata from entering the supported update path.

The installed-tree acceptance suite and repository-local static guards
complement focused tests; they do not prove that every third-party component or
hardware-specific path is vulnerability-free.

## Reporting

Do not publish exploit details in a public issue. GitHub private vulnerability
reporting is not currently enabled for this repository. Until a dedicated
private channel is published, open a detail-free issue asking the maintainers
to establish private contact.
