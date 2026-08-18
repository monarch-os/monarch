echo "Replace the bash menu extension sample with its JSONC equivalent"

# The menu is data now, so ~/.config/monarch/extensions/menu.sh documents an
# override mechanism that no longer exists: it explained how to redefine
# show_*_menu functions, and monarch-menu has none left.
#
# Only the shipped sample is removed. A menu.sh the user actually wrote is left
# in place — it stops being read either way, but deleting someone's file to
# tidy up is not this migration's call.

sample="$HOME/.config/monarch/extensions/menu.sh"

if [[ -f $sample ]] && ! grep -qvE '^\s*(#.*)?$' "$sample"; then
  rm -f "$sample"
elif [[ -f $sample ]]; then
  echo "  Kept $sample — it has content of your own, but the menu no longer reads it."
  echo "  Port it to ~/.config/monarch/extensions/monarch-menu.jsonc (see that file's header)."
fi

new_sample="$MONARCH_PATH/config/monarch/extensions/monarch-menu.jsonc"
target="$HOME/.config/monarch/extensions/monarch-menu.jsonc"

if [[ -f $new_sample && ! -f $target ]]; then
  mkdir -p "$(dirname "$target")"
  cp "$new_sample" "$target"
fi
