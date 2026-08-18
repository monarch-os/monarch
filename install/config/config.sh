# Copy over Monarch configs
mkdir -p ~/.config
cp -R "$MONARCH_PATH"/config/* ~/.config/

# Noctalia v5 discovers local plugins under ~/.local/share/noctalia/plugins/,
# not ~/.config/, so the bar indicators are seeded separately from config/.
mkdir -p ~/.local/share/noctalia/plugins
cp -R "$MONARCH_PATH"/default/noctalia/plugins/* ~/.local/share/noctalia/plugins/

# Put the Monarch backgrounds where config.toml's wallpaper.directory points.
#
# v4 also had to seed ~/.cache/noctalia/wallpapers.json here, because it resolved
# the on-screen wallpaper from that cache and fell back to its bundled
# noctalia.png when the file was missing — a visible race, since Monarch only
# applies the wallpaper over IPC once the shell is already up. v5 resolves it
# from wallpaper.directory instead, so dropping the copy below into place is
# enough: verified by cold-starting the shell with no persisted wallpaper state
# at all, which still painted the Monarch background on the first frame.
#
# The "Privacy Update" telemetry wizard that used to be seeded around here is
# gone too — v5 has no wizard and no changelog prompt, only the plain
# shell.telemetry_enabled opt-out that config.toml sets.
monarch_bg_src="$MONARCH_PATH/themes/monarch"
monarch_bg_dir="$HOME/.config/monarch/backgrounds/monarch"
if [[ -d $monarch_bg_src ]]; then
  mkdir -p "$monarch_bg_dir"
  cp -rn "$monarch_bg_src/." "$monarch_bg_dir/" 2>/dev/null || true
fi

# Use default RC from Monarch
cp "$MONARCH_PATH"/default/bashrc ~/.bashrc

# Install ZSH
cp "$MONARCH_PATH"/default/zshrc ~/.zshrc

# Change shell
sudo chsh -s /bin/zsh ${USER}