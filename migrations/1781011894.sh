echo "Default the Noctalia fixed font to a Nerd Font so bar/workspace glyphs stay centred"

# Noctalia renders the Workspace-widget pill glyphs (and other fixed-font UI)
# with Settings.data.ui.fontFixed. Our shipped default left it unset, so Noctalia
# fell back to its own default "monospace", which fontconfig may resolve to a font
# without the nerd glyphs -> per-codepoint fallback with mismatched metrics, so the
# workspace icons render off-centre. Pin it to JetBrainsMono Nerd Font Mono (already
# a Monarch dependency, used by the terminals) to match the new shipped default.
#
# Only touch installs that are still on the old default ("monospace") or have no
# ui.fontFixed at all -- never override a font the user deliberately chose.
NOCTALIA_CFG="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f "$NOCTALIA_CFG" ]]; then
  current=$(jq -r '.ui.fontFixed // "monospace"' "$NOCTALIA_CFG" 2>/dev/null)
  if [[ "$current" == "monospace" ]]; then
    echo "  Setting ui.fontFixed = JetBrainsMono Nerd Font Mono..."
    tmp=$(mktemp)
    if jq '.ui = ((.ui // {}) + {"fontFixed": "JetBrainsMono Nerd Font Mono"})' \
         "$NOCTALIA_CFG" >"$tmp"; then
      mv "$tmp" "$NOCTALIA_CFG"
    else
      rm -f "$tmp"
      echo "  Warning: could not update $NOCTALIA_CFG; set ui.fontFixed manually." >&2
    fi
  else
    echo "  ui.fontFixed already customised ($current); leaving it untouched."
  fi
fi
