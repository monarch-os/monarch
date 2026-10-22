# Omarchy P0 — authentication and privilege review

Date: 2026-10-22. Baseline: `0d6010d7a`. Modules: targeted code and secrets review.
API, frontend, dependencies, Terraform and CI/CD are outside this change's scope.
No general secret/history scan or overall security posture assessment was done.

## H-1: Temporary sudo expiry excludes suspended time

Severity: High. Confidence: HIGH. CWE-613.
Status: IN PROGRESS — local fix tested; installed acceptance and deployment pending.
File: `bin/monarch-sudo-passwordless`.

The previous unrestricted `NOPASSWD` grant depended on a monotonic `--on-active`
timer. After suspension beyond its advertised deadline, a session process could
still use the remaining awake-time grant. Explicit opt-in and boot cleanup did
not enforce wall-clock expiry.

Following Omarchy's command organization, one script provides the interactive
flow and internal `__*` actions. Privileged calls always select the fixed
packaged `/usr/bin/monarch-sudo-passwordless`, never the caller's checkout.
The internal dispatcher now publishes a validated UTC `NOTAFTER` rule
atomically, after arming an absolute timer. UID validation, serialization and
per-grant tokens protect renewal from obsolete callbacks. System reconciliation
revokes exact legacy unbounded rules. The menu queries grant validity. No
permanent-passwordless option is introduced.

## H-2: Factory reset elevates mutable checkout code

Severity: High. Confidence: HIGH. CWE-829.
Status: IN PROGRESS — local fix tested; installed acceptance and deployment pending.
File: `bin/monarch-system-factory-reset`.

The previous `$0` elevation could load a user-writable copy changed while an
administrator authenticated. Sudo authentication was still required; this is
not an unauthenticated privilege escalation. Reset now compares against and
elevates the fixed packaged command, rejects divergent copies, and pins the
privileged runtime and command search path.

## H-3: Fingerprint setup publishes session-selected PAM code

Severity: High. Confidence: HIGH. CWE-829.
Status: IN PROGRESS — local fix tested; installed acceptance and deployment pending.
Files: `bin/monarch-setup-security-fingerprint`,
`install/reconcile/fingerprint-gate.sh`, `install/reconcile/system.sh`.

The previous setup/reconciliation copied a helper from `MONARCH_PATH` into a
privileged PAM executable path. Administrator authorization was required, but
the source could be replaced by another session process before that copy.

PAM now references the packaged `/usr/bin/monarch-hw-laptop-closed`. Reconciliation
validates the replacement and its ancestry before atomically replacing exact
legacy lines or repairing a missing stock gate. Custom policy is preserved.
Legacy helpers are removed only if identical to the package and unreferenced.

## Validation

Isolated fixtures exercise failed publication and renewal, abrupt termination,
stale callbacks, expiry, invalid identities, mutable checkout replacement,
hostile environment, package permissions and PAM preservation. Fixture source
substitutions are checked, and redundant source assertions use behavioral checks.
The real `visudo` parser accepts the bounded rule; package staging includes the
executable command and reconciler. No live sudo grant, PAM edit or reset was run.

Installed-package, fingerprint and suspension acceptance remain outstanding;
the dev VM was unavailable. Two unrelated full-suite failures (network and
Windows VM mount boundaries) reproduce on the unchanged baseline.

Already covered: invoking-account fingerprint deletion, polkit `system-auth`
fallback, hook/state names and RDP passwords outside argv.

Source: [Omarchy 4.5.0-rc1](https://github.com/omacom/omarchy/releases/tag/v4.5.0-rc1).
