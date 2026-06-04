echo "Replace waybar/walker/mako/hyprlock/swayosd/swaybg with Noctalia desktop shell"

# 1. Stop the now-retired services so they don't fight Noctalia for layer-shell
#    real-estate during the switchover.
for proc in waybar walker elephant mako hyprlock swayosd-server swayosd-libinput-backend swaybg; do
  pkill -x "$proc" 2>/dev/null || true
done

systemctl --user disable --now swayosd-libinput-backend.service swayosd-server.service 2>/dev/null || true
systemctl --user disable --now app-walker@autostart.service 2>/dev/null || true
systemctl --user disable --now elephant.service 2>/dev/null || true

# 1b. Offer to carry the waybar workspace glyphs over to Niri. What people
#     "renamed" under Hyprland was really a waybar `hyprland/workspaces`
#     format-icons map (1..10 -> glyph). Niri shows the workspace *name* in the
#     Noctalia bar, so we import that map as names into workspaces.conf. This
#     MUST run before step 2 backs up & removes ~/.config/waybar; step 7's
#     monarch-refresh-niri then turns the names into declarations + Mod+N binds.
ws_conf="$HOME/.config/niri/workspaces.conf"
waybar_cfg="$HOME/.config/waybar/config.jsonc"

# Emit 10 lines: the glyph for slot N, or N itself when that slot is empty or
# missing (so the 1..10 alignment is never shifted). Pure awk, JSONC-tolerant.
ws_icons_extract() {
  local cfg="$1"
  [[ -f $cfg ]] || return 1
  awk '
    !inmod && /"hyprland\/workspaces"[[:space:]]*:/ { inmod=1 }
    inmod {
      o=gsub(/\{/,"{"); c=gsub(/\}/,"}"); depth += o - c
      if (o>0) seenopen=1
      if (match($0, /"[0-9]+"[[:space:]]*:[[:space:]]*"/)) {
        key=substr($0,RSTART+1); sub(/".*/,"",key)
        rest=substr($0,RSTART+RLENGTH); q=index(rest,"\"")
        icon[key]=(q>0)?substr(rest,1,q-1):""
      }
      if (seenopen && depth<=0) { for(n=1;n<=10;n++) print (icon[n]!="")?icon[n]:n; exit }
    }
  ' "$cfg"
}

# True when workspaces.conf is absent or still the shipped 1..10 default — never
# clobber names the user already chose.
ws_conf_is_pristine() {
  local f="$1" data
  [[ -f $f ]] || return 0
  data=$(grep -vE '^[[:space:]]*(#|$)' "$f" | tr -d '[:space:]')
  [[ -z $data || $data == "12345678910" ]]
}

ws_mapped=$(ws_icons_extract "$waybar_cfg" 2>/dev/null || true)
if [[ -n $ws_mapped ]] \
   && [[ $(printf '%s' "$ws_mapped" | tr -d '[:space:]') != "12345678910" ]] \
   && ws_conf_is_pristine "$ws_conf" \
   && command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
  echo "Your waybar workspaces used custom icons:"
  printf '%s\n' "$ws_mapped" | awk '{printf "  %2d  ->  %s\n", NR, $0}'
  if gum confirm "Carry these over as your Niri workspace names?"; then
    mkdir -p "$(dirname "$ws_conf")"
    {
      echo "# Imported from waybar hyprland/workspaces format-icons by the"
      echo "# Noctalia migration. One name per line = workspaces 1..10."
      echo "# Edit freely, then run: monarch refresh niri"
      printf '%s\n' "$ws_mapped"
    } >"$ws_conf"
    echo "Imported into $ws_conf"
  fi
fi

# 2. Drop the obsolete user configs and autostart entries.
for d in waybar walker hyprlock swayosd mako elephant; do
  if [[ -d $HOME/.config/$d ]]; then
    mv "$HOME/.config/$d" "$HOME/.config/$d.backup-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
done
rm -f "$HOME/.config/autostart/walker.desktop"
rm -rf "$HOME/.config/systemd/user/app-walker@autostart.service.d"
sudo rm -f /etc/pacman.d/hooks/walker-restart.hook

# 3. Install Noctalia and its supporting tooling. Falls back to AUR for
#    noctalia-shell since it has not yet landed in the Monarch repo.
for pkg in cliphist fuzzel ddcutil; do
  monarch-pkg-missing "$pkg" && monarch-pkg-add "$pkg" || true
done
if monarch-pkg-missing noctalia-shell; then
  monarch-pkg-aur-add noctalia-shell || true
fi

# 4. Remove the now-unused packages — keep installed copies if the user is
#    still relying on them outside Monarch (best-effort drop only).
for pkg in waybar omarchy-walker walker mako swaybg swayosd hyprlock; do
  if monarch-pkg-present "$pkg"; then
    monarch-pkg-drop "$pkg" 2>/dev/null || true
  fi
done

# 5. Seed the Noctalia user config and the shipped Monarch color scheme from
#    Monarch's defaults. Theming is delegated to Noctalia: a single "Monarch"
#    scheme (dark + light blocks) ships as a real file under colorschemes/.
rm -f "$HOME/.config/noctalia/colorschemes/Monarch/Monarch.json" # drop any old symlink
monarch-refresh-config noctalia/settings.json || true
monarch-refresh-config noctalia/colorschemes/Monarch/Monarch.json || true

# 6. Apply the residual system theming layer (wallpaper, Chromium, keyboard).
#    Redirect stdout so it runs non-interactively (skips the heavy Plymouth path).
monarch-cmd-present monarch-theme-apply && monarch-theme-apply >/dev/null 2>&1 || true

# 6a. Carry the user's pre-Niri wallpaper across. Under Hyprland the selected
#     background was a symlink (~/.config/monarch/current/background) maintained
#     by the old theme engine; step 6 above just forced the Monarch default, so
#     restore the user's actual pick instead. We copy the file into the Monarch
#     scheme folder so it survives the 6b teardown (which deletes the old theme's
#     shipped backgrounds) and shows up in Noctalia's picker, then make it the
#     applied wallpaper. wallpaper.directory stays pointed at the scheme folder,
#     so future color regenerations (monarch-theme-apply on dark/light toggle)
#     no-op and never reset the pick. MUST run before 6b removes current/theme.
old_bg=$(readlink -f "$HOME/.config/monarch/current/background" 2>/dev/null || true)
if [[ -n $old_bg && -f $old_bg ]] && command -v jq >/dev/null; then
  dest_dir="$HOME/.config/monarch/backgrounds/monarch"
  mkdir -p "$dest_dir"
  dest="$dest_dir/$(basename "$old_bg")"
  if [[ ! -e $dest ]]; then
    cp "$old_bg" "$dest" 2>/dev/null || dest="$old_bg"
  elif ! cmp -s "$old_bg" "$dest"; then
    # Same basename, different image (e.g. a theme's omarchy.png) — keep both.
    dest="$dest_dir/prev-$(basename "$old_bg")"
    cp "$old_bg" "$dest" 2>/dev/null || dest="$old_bg"
  fi

  # Seed the cache so Noctalia paints it on frame one (step 7 launches it), and
  # push it over IPC too in case the shell is already alive.
  wp_file="$HOME/.cache/noctalia/wallpapers.json"
  mkdir -p "$(dirname "$wp_file")"
  [[ -f $wp_file ]] || echo '{}' >"$wp_file"
  tmp=$(mktemp)
  if jq --arg p "$dest" '.wallpapers = (.wallpapers // {})
       | .usedRandomWallpapers = (.usedRandomWallpapers // {})
       | .defaultWallpaper = $p' "$wp_file" >"$tmp"; then
    mv "$tmp" "$wp_file"
  else
    rm -f "$tmp"
  fi
  if pgrep -f 'qs.*noctalia-shell' >/dev/null 2>&1; then
    qs -c noctalia-shell ipc call wallpaper set "$dest" "" >/dev/null 2>&1 || true
    qs -c noctalia-shell ipc call wallpaper refresh >/dev/null 2>&1 || true
  fi
  echo "Carried your previous wallpaper over to Noctalia: $(basename "$dest")"
fi

# 6b. Tear down the legacy Monarch theme engine. Theming is fully delegated to
#     Noctalia now, so drop the old home-grown theme-engine state and repoint
#     btop/helix/alacritty at Noctalia's theme.
rm -rf "$HOME/.config/monarch/themes" \
  "$HOME/.config/monarch/current/theme" \
  "$HOME/.config/monarch/current/next-theme" \
  "$HOME/.config/monarch/current/theme.name"
rm -f "$HOME/.config/monarch/current/background" # dead symlink; wallpaper carried over in 6a
rm -f "$HOME/.config/btop/themes/current.theme" # btop now uses color_theme="noctalia"
rm -f "$HOME/.config/helix/themes/monarch.toml" # helix now uses theme="noctalia"
if [[ -f $HOME/.config/helix/config.toml ]]; then
  sed -i 's/^theme = "monarch"$/theme = "noctalia"/' "$HOME/.config/helix/config.toml"
fi
# Alacritty imported the engine's generated theme via a dotted `general.import`.
# Drop the now-dead-path import: left in place, Noctalia's apply hook fails to
# see it as a [general] table and prepends a second `[general] import` block —
# two `general.import` keys, an illegal TOML duplicate Alacritty rejects with
# "Unused config key: general". Then ensure a single Noctalia import remains.
alacritty_cfg="$HOME/.config/alacritty/alacritty.toml"
if [[ -f $alacritty_cfg ]]; then
  sed -i '\#monarch/current/theme#d' "$alacritty_cfg"
  grep -q 'themes/noctalia.toml' "$alacritty_cfg" ||
    sed -i '1i [general]\nimport = [ "~/.config/alacritty/themes/noctalia.toml" ]\n' "$alacritty_cfg"
fi

# 7. Refresh Niri so the new autostart/binds pick up Noctalia, then launch it
#    immediately if a Niri session is already running.
monarch-refresh-niri || true
if pgrep -x niri >/dev/null 2>&1 && ! pgrep -f 'qs.*noctalia-shell' >/dev/null 2>&1; then
  setsid uwsm-app -- qs -c noctalia-shell >/dev/null 2>&1 &
fi
