echo "Turn on external monitor brightness, and move the terminal font size where it can be changed"

# Noctalia drives DDC/CI only when asked, and Monarch never asked: ddcutil has
# been in monarch-base.packages all along and nothing set
# brightness.enable_ddcutil, so the brightness widget reached the laptop panel
# and silently nothing else.
config="$HOME/.config/noctalia/config.toml"
if [[ -f $config ]] && ! grep -q '^\[brightness\]' "$config"; then
  echo "  Enabling Noctalia's DDC backend."
  printf '\n[brightness]\nenable_ddcutil = true\n' >>"$config"
fi

# monarch-display-text-size needs a file it can rewrite. alacritty loads imports
# before the importing file, so a size left in alacritty.toml would win over
# anything the command wrote — it moves here instead, keeping whatever size the
# user had rather than resetting them to the Monarch default.
alacritty="$HOME/.config/alacritty/alacritty.toml"
override="$HOME/.config/alacritty/monarch-text-size.toml"

if [[ -f $alacritty ]] && ! grep -q 'monarch-text-size.toml' "$alacritty"; then
  size=$(awk -F= '/^[[:space:]]*size[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$alacritty")
  echo "  Moving the terminal font size into monarch-text-size.toml."

  cat >"$override" <<EOF
# Rewritten whole by monarch-display-text-size. 9 is the Monarch default, the
# size 100% scales from; alacritty.toml imports this and sets no size itself.
[font]
size = ${size:-9}
EOF

  sed -i '/^[[:space:]]*size[[:space:]]*=/d' "$alacritty"
  # The import list is one line on the shipped config and may be several on a
  # hand-edited one; add ours to whichever shape is there.
  if grep -q '^general.import = \[' "$alacritty"; then
    sed -i '0,/^general\.import = \[/s|^general\.import = \[\(.*\)\]$|general.import = [\1, "~/.config/alacritty/monarch-text-size.toml" ]|' "$alacritty"
    sed -i '0,/^general\.import = \[$/s|^general\.import = \[$|general.import = [\n  "~/.config/alacritty/monarch-text-size.toml",|' "$alacritty"
  else
    sed -i '1i general.import = [ "~/.config/alacritty/monarch-text-size.toml" ]' "$alacritty"
  fi
fi
