echo "Move an existing Noctalia v4 install onto v5"

# Fresh installs never reach this: preflight/migrations.sh stamps every migration
# before the first one fires. This is only the upgrade path for machines still
# running the Quickshell-based v4 shell, which shares neither its config format,
# its state files, nor its package with v5.

if monarch-pkg-missing noctalia-shell && [[ ! -f $HOME/.config/noctalia/settings.json ]]; then
  echo "  No Noctalia v4 install found; nothing to do."
  exit 0
fi

pkill -f 'qs.*noctalia-shell' 2>/dev/null || true

# v5's `noctalia` declares neither conflicts nor replaces against `noctalia-shell`,
# so pacman is content to keep both. Install before dropping: -Rns spares the deps
# the two share (pam, polkit, jemalloc, libpipewire) only once v5 is there to
# require them. If the install fails, stop rather than leave the machine shell-less.
if monarch-pkg-missing noctalia; then
  echo "  Installing Noctalia v5"
  if ! monarch-pkg-add noctalia; then
    echo "  Could not install noctalia; leaving v4 in place."
    exit 1
  fi
fi

if monarch-pkg-present noctalia-shell; then
  echo "  Removing Noctalia v4 (noctalia-qs goes with it)"
  monarch-pkg-drop noctalia-shell
fi

echo "  Seeding the Monarch v5 Noctalia config"
monarch-refresh-config noctalia/config.toml
monarch-refresh-config noctalia/palettes/Monarch.json

# templates/ survives the version change: it still holds the sddm and herdr
# inputs monarch-theme-apply renders.
mkdir -p "$HOME/.config/noctalia/templates"
cp -rf "$MONARCH_PATH"/config/noctalia/templates/. "$HOME/.config/noctalia/templates/"

# user-templates.toml is not merely inert — v5 merges every *.toml in this
# directory and rejects its [templates.*] sections as unknown. colors.json is
# deliberately absent from this list: monarch-sddm-theme and
# monarch-plymouth-apply still read it.
echo "  Removing v4 state"
rm -f "$HOME"/.config/noctalia/settings.json "$HOME"/.config/noctalia/settings.json.bak.*
rm -f "$HOME"/.config/noctalia/user-templates.toml "$HOME"/.config/noctalia/user-templates.toml.bak.*
rm -f "$HOME/.config/noctalia/plugins.json"
rm -rf "$HOME/.config/noctalia/colorschemes" "$HOME/.config/noctalia/plugins"
rm -f "$HOME/.cache/noctalia/shell-state.json" "$HOME/.cache/noctalia/wallpapers.json"
rm -rf "$HOME/.cache/noctalia-qs"

# Whatever user-templates.toml registered is unreachable now, so the only inputs
# worth keeping are the ones Monarch still ships.
for template in "$HOME"/.config/noctalia/templates/*; do
  [[ -e $template ]] || continue
  [[ -e "$MONARCH_PATH/config/noctalia/templates/$(basename "$template")" ]] || rm -f "$template"
done

# v5 discovers plugins under ~/.local/share/noctalia/plugins/, not ~/.config/.
echo "  Seeding the Monarch plugins"
mkdir -p "$HOME/.local/share/noctalia/plugins"
cp -rf "$MONARCH_PATH"/default/noctalia/plugins/. "$HOME/.local/share/noctalia/plugins/"

# v4 kept the lock-screen reader armed through two settings.json keys just deleted.
if [[ -f $HOME/.local/state/monarch/fingerprint-enabled ]]; then
  echo "  Carrying the fingerprint toggle over"
  cat >"$HOME/.config/noctalia/monarch-fingerprint.toml" <<'EOF'
# Managed by Monarch (monarch-setup-security-fingerprint).
# Removed by monarch-remove-security-fingerprint.
[lockscreen]
fingerprint = true
EOF
fi

# config.kdl still spawns `qs -c noctalia-shell` until it is rebuilt from the
# Monarch default, which spawns `noctalia -d`.
monarch-refresh-niri

started=0
if pgrep -x niri >/dev/null 2>&1 && ! pgrep -x noctalia >/dev/null 2>&1; then
  setsid uwsm-app -- noctalia -d >/dev/null 2>&1 &
  started=1
fi

if ((started)); then
  for _ in {1..10}; do
    noctalia msg status >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

# Discovery is not activation: a seeded plugin stays disabled until asked for,
# and `plugins enable` needs the daemon listening.
if noctalia msg status >/dev/null 2>&1; then
  for plugin in monarch/indicators monarch/agents monarch/menu; do
    noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || true
  done
  monarch-theme-apply >/dev/null 2>&1 || true
else
  # A migration is stamped as done whether or not the daemon answered, so this
  # cannot just wait for the next run. Defer it to the next boot instead; the
  # hook removes itself once it lands, and keeps trying until then.
  hook_dir="$HOME/.config/monarch/hooks/post-boot.d"
  mkdir -p "$hook_dir"
  cat >"$hook_dir/noctalia-v5-plugins" <<'HOOK'
#!/bin/bash
# One-shot leftover of the Noctalia v4-to-v5 migration. Self-removing.

noctalia msg status >/dev/null 2>&1 || exit 0

for plugin in monarch/indicators monarch/agents monarch/menu; do
  noctalia msg plugins enable "$plugin" >/dev/null 2>&1 || true
done
monarch-theme-apply >/dev/null 2>&1 || true

rm -f "$0"
HOOK
  chmod 755 "$hook_dir/noctalia-v5-plugins"
  echo "  Noctalia is not running; its plugins will be enabled on the next boot."
fi
