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

# Resolve the persistent workspace NAMES from the same source as
# monarch-refresh-niri's generate_workspaces_kdl(), so the AZERTY sym binds
# target the exact same workspace as the Mod+<digit> binds in workspaces.kdl.
# niri references workspaces by name (the index is just a per-monitor slot, not
# a stable identity), so a slot number only works while the name IS that number;
# read the real names here and keep these parse rules in lockstep with that
# function. Missing file / blank line / out-of-range slot falls back to the slot
# number, exactly like generate_workspaces_kdl's 1..10 default.
ws_conf="$HOME/.config/niri/workspaces.conf"
ws_names=()
if (( ${#azerty_binds[@]} > 0 )) && [[ -r $ws_conf ]]; then
  workspace_helpers="${MONARCH_INSTALL:-${MONARCH_PATH:-/usr/share/monarch}/install}/helpers/workspaces.sh"
  source "$workspace_helpers" || {
    status=$?
    return "$status" 2>/dev/null || exit "$status"
  }
  monarch_read_workspace_names "$ws_conf" ws_names
fi

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
  if (( switch_at_startup == 1 )); then
    echo
    echo "// us is index 0 (kept first to resolve Mod+letter). Switch the"
    echo "// active layout to index 1 ($layout) at startup so typing"
    echo "// remains in the user's preferred layout."
    echo "spawn-at-startup \"niri\" \"msg\" \"action\" \"switch-layout\" \"1\""
  fi
  if (( ${#azerty_binds[@]} > 0 )); then
    echo
    echo "// AZERTY top-row workspace shortcuts. niri resolves binds on the key's"
    echo "// BASE (unshifted) keysym, and an ASCII sym (& \" ' ( - _) from the active"
    echo "// layout is matched DIRECTLY — it never falls back to the first (us)"
    echo "// layout for Latin resolution. That holds with Shift held too, so both"
    echo "// Mod+<digit> AND Mod+Shift+<digit> miss on these keys and must be bound"
    echo "// explicitly to the sym. (Keys 2/7/9/0 keep working: their base é/è/ç/à"
    echo "// aren't ASCII, so niri does fall back to us and resolves the real digit.)"
    echo "//"
    echo "// Mod+Shift+<sym> is emitted alongside the focus bind, else the move would"
    echo "// hit whatever binds.kdl maps the sym to — e.g. Mod+Shift+6 -> Mod+Shift+minus"
    echo "// = shrink window height. keyboard.kdl is included after binds.kdl, so the"
    echo "// later definition wins and overrides that collision."
    echo "binds {"
    for pair in "${azerty_binds[@]}"; do
      sym="${pair%=*}"
      ws="${pair#*=}"
      # Target the persistent NAME at this slot, not the slot number, so renaming
      # a workspace in workspaces.conf keeps these binds aligned with workspaces.kdl.
      idx=$((ws - 1)); name="$ws"
      (( idx < ${#ws_names[@]} )) && [[ -n ${ws_names[idx]:-} ]] && name="${ws_names[idx]}"
      esc="${name//\\/\\\\}"; esc="${esc//\"/\\\"}"
      printf '    Mod+%s hotkey-overlay-title="Workspace %s" { focus-workspace "%s"; }\n' "$sym" "$ws" "$esc"
      printf '    Mod+Shift+%s hotkey-overlay-title="Move column to workspace %s" { move-column-to-workspace "%s"; }\n' "$sym" "$ws" "$esc"
    done
    echo "}"
  fi
} >"$target"
