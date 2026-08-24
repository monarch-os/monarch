# Copy over Monarch configs
mkdir -p ~/.config
cp -R "$MONARCH_PATH"/config/* ~/.config/

# Monarch already owns the initial palette, wallpaper and telemetry choice.
mkdir -p ~/.local/state/noctalia
touch ~/.local/state/noctalia/.setup-complete

# Noctalia v5 discovers local plugins under ~/.local/share/noctalia/plugins/,
# not ~/.config/, so the bar indicators are seeded separately from config/.
mkdir -p ~/.local/share/noctalia/plugins
cp -R "$MONARCH_PATH"/default/noctalia/plugins/* ~/.local/share/noctalia/plugins/

# Seed the Monarch scheme's user background folder. This is the per-scheme user
# dir (mirroring omarchy's ~/.config/omarchy/backgrounds/<theme>/), not the
# folder wallpaper.directory points at: config.toml pins that at a symlink farm
# (~/.config/monarch/backgrounds/current) which the config-stage monarch-theme-apply
# below rebuilds from this folder before the shell ever starts.
#
# v4 also had to seed ~/.cache/noctalia/wallpapers.json here, because it resolved
# the on-screen wallpaper from that cache and fell back to its bundled
# noctalia.png when the file was missing. v5 has no such cache, so that seeding is
# gone — but the race it papered over is not: Monarch can only apply a wallpaper
# over IPC once the shell is up, and the config-stage monarch-theme-apply runs
# before that. A booted VM came up on Noctalia's own bundled wallpaper. Copying
# the files here is therefore necessary but not sufficient; what actually paints
# the first Monarch background is sync_wallpaper's first-run stamp
# (~/.local/state/monarch/wallpaper-applied), on the first colors_changed hook
# after the shell starts.
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
