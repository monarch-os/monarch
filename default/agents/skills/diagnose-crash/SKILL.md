---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine from a systemd-coredump core
  dump. Use for crashes, segfaults, SIGSEGV, SIGABRT, core dumps, coredumpctl,
  backtraces, or a Process crashed notification.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible story.

## Establish the facts

Start with `coredumpctl info <pid>`. Note the command line as well as the
backtrace: it often reveals what the program was doing. Use `coredumpctl list`
to determine whether this was isolated or recurrent.

Check resource exhaustion before blaming the process. Inspect `free -h` and the
journal for OOM kills, then correlate the crash timestamp with nearby journal
entries, filesystem changes, and recent package updates.

Read every thread stack. Other threads reveal in-flight work such as image
loading, IPC, plugins, or GPU queues. Identify third-party libraries, plugins,
extensions, and out-of-tree drivers, but do not assign blame without evidence.

## Symbolize when possible

Arch provides a public debuginfod server:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

A core is a copy of process memory and may contain passwords, tokens, private
documents, or other secrets. Never upload it. Keep temporary copies at a fresh
`mktemp` path and delete them after diagnosis. If symbols are unavailable, say
so rather than inventing function names.

## Report

Explain:

1. What crashed and what it was doing.
2. What the evidence proves, separately from any inference.
3. Whether user data was lost and where it may be recovered.
4. Whether recurrence is likely and what could avoid it.

Diagnosis is read-only. Do not fix, reconfigure, upload, or file an issue unless
the user separately asks for it. Remove only temporary core copies you created.

If the evidence indicates a Monarch bug, read [`reporting.md`](reporting.md).
