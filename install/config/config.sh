# Copy over Monarch configs
mkdir -p ~/.config
cp -R ~/.local/share/monarch/config/* ~/.config/

# Seed Noctalia's shell-state BEFORE its first launch to suppress the "Privacy
# Update" telemetry wizard. Because Monarch ships ~/.config/noctalia/settings.json
# above, Noctalia never sees a fresh install (isFreshInstall=false); it then
# fires the wizard whenever changelogState.lastSeenVersion is empty or < 4.0.2
# (Services/Noctalia/UpdateService.qml: shouldShowTelemetryWizard). Seeding the
# installed version here — before the Niri session starts qs — closes that gap.
# The migration and `monarch refresh noctalia` cover the upgrade/manual paths.
state_file="$HOME/.cache/noctalia/shell-state.json"
mkdir -p "$(dirname "$state_file")"
[[ -f $state_file ]] || echo '{}' >"$state_file"
ver=$(pacman -Q noctalia-shell 2>/dev/null | awk '{print $2}' | cut -d- -f1)
[[ -z $ver ]] && ver="4.0.2" # telemetryIntroVersion floor
if command -v jq >/dev/null; then
  tmp=$(mktemp)
  if jq --arg v "$ver" '.changelogState = ((.changelogState // {}) | .lastSeenVersion = $v)' "$state_file" >"$tmp"; then
    mv "$tmp" "$state_file"
  else
    rm -f "$tmp"
  fi
fi

# Seed the Monarch wallpaper into Noctalia's cache BEFORE its first launch.
# Noctalia resolves the on-screen wallpaper from ~/.cache/noctalia/wallpapers.json
# (Services/UI/WallpaperService.qml); a missing file falls back to its bundled
# noctalia.png. Monarch's runtime layer (monarch-theme-apply) only applies the
# wallpaper over IPC once the shell is already up — a visible race that leaves
# the default showing. Seeding the cache here paints the Monarch wallpaper on
# frame one. Mirrors the scheme folder that settings.json's wallpaper.directory
# points at (~/.config/monarch/backgrounds/monarch).
monarch_bg_src="$HOME/.local/share/monarch/themes/monarch"
monarch_bg_dir="$HOME/.config/monarch/backgrounds/monarch"
if [[ -d $monarch_bg_src ]] && command -v jq >/dev/null; then
  mkdir -p "$monarch_bg_dir"
  cp -rn "$monarch_bg_src/." "$monarch_bg_dir/" 2>/dev/null || true
  first_bg=$(find -L "$monarch_bg_dir" -maxdepth 1 -type f | sort | head -n1)
  if [[ -n $first_bg ]]; then
    wp_file="$HOME/.cache/noctalia/wallpapers.json"
    mkdir -p "$(dirname "$wp_file")"
    [[ -f $wp_file ]] || echo '{}' >"$wp_file"
    tmp=$(mktemp)
    if jq --arg p "$first_bg" '.wallpapers = (.wallpapers // {})
         | .usedRandomWallpapers = (.usedRandomWallpapers // {})
         | .defaultWallpaper = $p' "$wp_file" >"$tmp"; then
      mv "$tmp" "$wp_file"
    else
      rm -f "$tmp"
    fi
  fi
fi

# Use default RC from Monarch
cp ~/.local/share/monarch/default/bashrc ~/.bashrc

# Install ZSH
cp ~/.local/share/monarch/default/zshrc ~/.zshrc

# Change shell
sudo chsh -s /bin/zsh ${USER}