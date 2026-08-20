echo "Uninstall the orphaned Elephant providers left behind by the Noctalia switch"

# The Noctalia migration (1779188617) stopped elephant, disabled elephant.service
# and backed up ~/.config/elephant — but its uninstall list only covered
# waybar/omarchy-walker/walker/mako/swaybg/swayosd/hyprlock. The Elephant
# providers were installed *explicitly* by 1758107878/1758107879, so
# `pacman -Rns omarchy-walker` did not reclaim them as unneeded dependencies
# either. They sit on every migrated machine as orphans with a dead service.
#
# Nothing in Monarch has referenced Elephant since the switch: config/elephant,
# default/elephant and install/config/walker-elephant.sh are all gone, and the
# launcher is fuzzel + Noctalia. libqalculate stays — it is still listed in
# install/monarch-base.packages on its own merits.

# Walker is the only consumer of the providers. If it is somehow still installed
# — someone re-added it deliberately after the switch — leave the whole set
# alone rather than breaking their launcher.
if monarch-pkg-present walker || monarch-pkg-present omarchy-walker; then
  echo "Walker is still installed — leaving its Elephant providers in place."
else
  # Enumerate what is actually installed rather than hard-coding the provider
  # list: elephant-all and hand-added providers (bookmarks, bitwarden, windows,
  # niriactions, ...) are just as orphaned, and pacman errors out on names it
  # does not know.
  mapfile -t elephant_pkgs < <(pacman -Qq 2>/dev/null | grep -E '^elephant(-|$)' || true)

  if ((${#elephant_pkgs[@]} > 0)); then
    echo "Removing ${#elephant_pkgs[@]} Elephant package(s): ${elephant_pkgs[*]}"
    # Best-effort: an out-of-tree package built against a provider would make
    # pacman refuse the whole transaction. Better to leave the orphans than to
    # fail the migration and hand the user a gum prompt they cannot act on.
    monarch-pkg-drop "${elephant_pkgs[@]}" || echo "Could not remove them (a dependent package is in the way) — skipping."
  fi

  # The unit ships inside the elephant package, so this only matters when the
  # drop above was skipped or partial. Disabling an absent unit is a no-op.
  systemctl --user disable --now elephant.service 2>/dev/null || true

  # 1770380577 / 1775679533 / 1778070145 seeded ~/.config/elephant/menus with
  # symlinks into $MONARCH_PATH/default/elephant, a directory that no longer
  # exists. 1779188617 backed the folder up, but the service could have
  # recreated it before it was stopped. Move it aside the same way rather than
  # deleting anything the user may have written.
  if [[ -d $HOME/.config/elephant ]]; then
    mv "$HOME/.config/elephant" "$HOME/.config/elephant.backup-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
fi

echo # Assure final success
