# Reporting a Crash Upstream to Monarch

Most application crashes belong to the application or library upstream, not to
Monarch. Monarch owns its commands, configuration, installer, migrations,
packaging, Niri integration, Noctalia plugins, and shipped themes.

Only prepare a Monarch report when evidence implicates that scope. Search open
and closed issues first using the program, signal, trigger, and distinctive
backtrace symbols. The same application crashing is not necessarily the same
bug.

Never file or comment without explicit user approval. Show the exact proposed
title and body first. Do not install or authenticate GitHub tooling on the
user's behalf.

Include reproduction steps, expected and actual behaviour, `monarch version`,
relevant diagnostics, and a redacted backtrace. Never attach or upload the core
dump: it may contain credentials and private user data.
