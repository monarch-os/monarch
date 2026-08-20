echo "Seed the Omarchy palettes as Monarch custom color schemes"

# Fresh installs get these from install/config/config.sh, which copies config/*
# into ~/.config. Existing installs need them placed here.
#
# Each palette carries the same block under both "dark" and "light": these themes
# have one appearance, and Noctalia rejects a custom palette outright when the
# block for the active mode is missing ("custom palette X not found or invalid;
# falling back to builtin"). The mode toggle therefore does not change them.

PALETTES="$MONARCH_PATH/config/noctalia/palettes"
DEST="$HOME/.config/noctalia/palettes"

if [[ -d $PALETTES ]]; then
  mkdir -p "$DEST"
  cp -f "$PALETTES"/*.json "$DEST/"
  echo "  Seeded $(ls "$PALETTES"/*.json | wc -l) palettes into ~/.config/noctalia/palettes"
fi
