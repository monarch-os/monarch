echo "Send Shift+Enter as CSI-u across terminals so TUIs can tell it apart from Enter"

# alacritty: replace the old Shift+Return binding with CSI-u encodings
alacritty_config="$HOME/.config/alacritty/alacritty.toml"
if [[ -f $alacritty_config ]] && ! grep -q '13;2u' "$alacritty_config"; then
  sed -i -E 's|^([[:space:]]*).*chars = "\\u001B\\r".*|\1# Send Shift+Return as CSI-u so TUIs can distinguish it from Return without treating it as Alt+Return.\n\1{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" },\n\1# Legacy encoding sends Alt+Shift+Return the same as Alt+Return; send CSI-u so TUIs can match Alt+Shift+Return.\n\1{ key = "Return", mods = "Alt\|Shift", chars = "\\u001B[13;4u" }|' "$alacritty_config"
fi

# foot: add CSI-u text bindings for Shift+Return and Alt+Shift+Return
foot_config="$HOME/.config/foot/foot.ini"
if [[ -f $foot_config ]] && ! grep -q '13;2u' "$foot_config"; then
  tmp_ins=$(mktemp)
  cat > "$tmp_ins" <<'BINDINGS'
# Send Shift+Return as CSI-u so TUIs can distinguish it from Return.
\x1b[13;2u=Shift+Return
# Send Alt+Shift+Return as CSI-u so TUIs can match Alt+Shift+Return.
\x1b[13;4u=Mod1+Shift+Return
BINDINGS

  if grep -q '^\[text-bindings\]$' "$foot_config"; then
    # Splice under the user's existing [text-bindings] section.
    awk -v insf="$tmp_ins" '
      { print }
      /^\[text-bindings\]$/ && !done { while ((getline line < insf) > 0) print line; done = 1 }
    ' "$foot_config" > "$foot_config.tmp" && mv "$foot_config.tmp" "$foot_config"
  else
    { printf '\n[text-bindings]\n'; cat "$tmp_ins"; } >> "$foot_config"
  fi

  rm -f "$tmp_ins"
fi

# ghostty: add CSI-u keybinds for Shift+Enter and Alt+Shift+Enter
ghostty_config="$HOME/.config/ghostty/config"
if [[ -f $ghostty_config ]] && ! grep -q 'csi:13;2u' "$ghostty_config"; then
  sed -i '/^keybind = control+insert=copy_to_clipboard$/a\# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter.\nkeybind = shift+enter=csi:13;2u\n# Legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so TUIs can match Alt+Shift+Enter.\nkeybind = alt+shift+enter=csi:13;4u' "$ghostty_config"
fi

# kitty: add CSI-u key mappings for Shift+Enter and Alt+Shift+Enter
kitty_config="$HOME/.config/kitty/kitty.conf"
if [[ -f $kitty_config ]] && ! grep -q '13;2u' "$kitty_config"; then
  sed -i '/^map shift+insert paste_from_clipboard$/a\# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter.\nmap shift+enter send_text all \\e[13;2u\n# Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so TUIs can match Alt+Shift+Enter.\nmap alt+shift+enter send_text all \\e[13;4u' "$kitty_config"
fi
