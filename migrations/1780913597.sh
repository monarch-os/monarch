echo "Replace tobi-try with try-rs-bin"

# tobi-try (Ruby) was Omarchy-only; try-rs-bin is the maintained Rust reimplementation
# of the same `try` scratch-directory tool, now served from the Monarch repo.
# Drop first so the new package's /usr/bin/try-rs doesn't conflict on upgrade.
monarch-pkg-drop tobi-try
monarch-pkg-add try-rs-bin

# tobi-try took its directory from a shell-init arg (`try init ~/Work/tries`).
# try-rs reads it from ~/.config/try-rs/config.toml instead, so seed the default
# (tries_path = ~/Work/tries) to keep existing scratch dirs in the same place.
monarch-refresh-config try-rs/config.toml
