# Omarchy P0 — screen-lock error propagation

Date: 2026-10-22. Baseline: `0d6010d7a`.

## I-1: Screen-lock IPC errors are discarded

Severity: Informational. Confidence: HIGH. CWE-252.
Status: IN PROGRESS — local fix tested; live lock/suspend acceptance pending.
File: `bin/monarch-system-lock`.

The wrapper previously returned zero after Noctalia failed with status 1 or 127,
because cleanup overwrote the exit status. It now retains and returns the IPC
status after best-effort cleanup and emits a diagnostic on failure.

No standalone authentication bypass was demonstrated. Noctalia independently
handles logind's bounded sleep-delay inhibitor and Wayland lock readiness.
IPC acceptance is not proof of readiness. The logind comment now names that
mechanism instead of a nonexistent Monarch service. The Omarchy Quickshell
`currentlyLocked()` fix does not apply to Noctalia's native stack.

## Validation

Isolated tests cover manual and lock-only modes, missing Noctalia, unsuccessful
IPC and absent cleanup targets. Existing screensaver/idle behavior is preserved.
No real lock or suspension was requested. The unavailable dev VM leaves live
lock-before-sleep acceptance outstanding.

Source: [Noctalia v5.3.0 sleep handling](https://github.com/noctalia-dev/noctalia/blob/v5.3.0/src/app/application_services.cpp).
