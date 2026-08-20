echo "Uninstall the orphaned Elephant providers left behind by the Noctalia switch"

# 1779188617 stopped elephant and disabled its service but never uninstalled it,
# and the providers were installed explicitly, so -Rns did not reclaim them.

# Walker is the only consumer; if someone re-added it, leave the set alone.
if monarch-pkg-present walker || monarch-pkg-present omarchy-walker; then
  echo "Walker is still installed — leaving its Elephant providers in place."
else
  # Enumerated, not hard-coded: pacman errors out on names it does not know.
  mapfile -t elephant_pkgs < <(pacman -Qq 2>/dev/null | grep -E '^elephant(-|$)' || true)

  if ((${#elephant_pkgs[@]} > 0)); then
    echo "Removing ${#elephant_pkgs[@]} Elephant package(s): ${elephant_pkgs[*]}"
    # Non-fatal: a failure here would stop `monarch migrate` on a gum prompt.
    monarch-pkg-drop "${elephant_pkgs[@]}" || echo "Could not remove them (a dependent package is in the way) — skipping."
  fi

  # Only matters when the drop was skipped or partial.
  systemctl --user disable --now elephant.service 2>/dev/null || true

  # 1779188617 backed this up, but the service could have recreated it since.
  if [[ -d $HOME/.config/elephant ]]; then
    mv "$HOME/.config/elephant" "$HOME/.config/elephant.backup-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
fi

echo # Assure final success
