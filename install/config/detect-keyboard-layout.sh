# Mirror the Arch console keyboard layout (XKBLAYOUT / XKBVARIANT) into
# ~/.config/niri/keyboard.kdl. The file is included by the Monarch Niri
# config and merges into the main input { keyboard { xkb { ... } } } block.
#
# For non-US layouts, prepend "us" so Niri can resolve Latin-key bindings
# (Mod+letter, accented-key digits like Mod+2/7/9/0 on AZERTY) via the
# first layout. Niri's documented behaviour:
# "Niri prioritizes the first configured XKB layout for resolving Latin
# keys." But Niri matches **ASCII printable** syms (& " ' ( - _ on AZERTY)
# from the active layout DIRECTLY, without falling back. That breaks
# Mod+1 / Mod+3 / Mod+4 / Mod+5 / Mod+6 / Mod+8 on AZERTY.
#
# The script therefore also emits a `binds { ... }` block with the explicit
# AZERTY-symbol bindings for workspace switching, so every top-row key
# triggers the expected workspace regardless of resolution path.
#
# Always (re)write the file so the result is idempotent: if XKBLAYOUT is
# unset, drop a stub comment so the include still resolves.

vconsole="/etc/vconsole.conf"
target="$HOME/.config/niri/keyboard.kdl"
mkdir -p "$(dirname "$target")"

layout=""
variant=""
if [[ -r $vconsole ]]; then
  layout=$(grep '^XKBLAYOUT=' "$vconsole" 2>/dev/null | cut -d= -f2 | tr -d '"')
  variant=$(grep '^XKBVARIANT=' "$vconsole" 2>/dev/null | cut -d= -f2 | tr -d '"')
fi

# Build the final layout / variant / options strings.
xkb_layout=""
xkb_variant=""
xkb_options=""
switch_at_startup=0
if [[ -n $layout && $layout != "us" ]]; then
  # Non-US: list us first so Mod+1..9 etc. resolve through the us layout,
  # then the user's layout for typing. variant is positional ("" for us,
  # "$variant" for the user's layout).
  xkb_layout="us,$layout"
  xkb_variant=",$variant"
  xkb_options="grp:alt_shift_toggle"
  switch_at_startup=1
elif [[ -n $layout ]]; then
  xkb_layout="$layout"
  xkb_variant="$variant"
fi

# Layout-specific workspace bindings for keys whose ASCII unshifted sym
# bypasses Niri's first-layout resolution. Each entry is "Mod+<sym>=<N>".
azerty_binds=()
case "$layout" in
  fr|be)
    azerty_binds=(
      "ampersand=1"   # &
      "quotedbl=3"    # "
      "apostrophe=4"  # '
      "parenleft=5"   # (
      "minus=6"       # - (overrides default Mod+Minus shrink column)
      "underscore=8"  # _
    )
    ;;
esac

{
  echo "// Generated from $vconsole by monarch detect-keyboard-layout."
  echo "// Edit ~/.config/niri/user.kdl to override these settings."
  if [[ -n $xkb_layout ]]; then
    echo "input {"
    echo "    keyboard {"
    echo "        xkb {"
    echo "            layout \"$xkb_layout\""
    [[ -n $xkb_variant ]] && echo "            variant \"$xkb_variant\""
    [[ -n $xkb_options ]] && echo "            options \"$xkb_options\""
    echo "        }"
    echo "    }"
    echo "}"
  fi
  if [[ $switch_at_startup -eq 1 ]]; then
    echo
    echo "// us is index 0 (kept first to resolve Mod+letter). Switch the"
    echo "// active layout to index 1 ($layout) at startup so typing"
    echo "// remains in the user's preferred layout."
    echo "spawn-at-startup \"niri\" \"msg\" \"action\" \"switch-layout\" \"1\""
  fi
  if [[ ${#azerty_binds[@]} -gt 0 ]]; then
    echo
    echo "// AZERTY top-row workspace shortcuts. ASCII syms (& \" ' ( - _) don't"
    echo "// fall back to the first layout for Latin resolution, so each one"
    echo "// must be bound explicitly to the matching workspace."
    echo "//"
    echo "// Note: Mod+Shift+<digit> already works via binds.kdl because pressing"
    echo "// Shift on AZERTY's top row produces the digit directly (no need for"
    echo "// per-sym bindings here)."
    echo "binds {"
    for pair in "${azerty_binds[@]}"; do
      sym="${pair%=*}"
      ws="${pair#*=}"
      printf '    Mod+%s hotkey-overlay-title="Workspace %s" { focus-workspace "%s"; }\n' "$sym" "$ws" "$ws"
    done
    echo "}"
  fi
} >"$target"
