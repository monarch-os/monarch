echo "Realign existing LazyVPN installs with the new monarch-lazyvpn package"

# LazyVPN moved from the old lazyvpn-init/lazyvpn-menu binaries to a single
# monarch-lazyvpn TUI (+ monarch-lazyvpn-status). Existing installs therefore
# have a broken keybind (the old Mod+Alt+V spawns the now-gone lazyvpn-menu), no
# app-launcher entry (the package no longer ships a .desktop), and no Noctalia
# status widget. Gate on the package being present so we only touch real users.
if ! monarch-pkg-present monarch-lazyvpn; then
  echo "  monarch-lazyvpn not installed; nothing to migrate."
  exit 0
fi

# 1. Rewrite the Niri keybinding block to spawn the new TUI and move it onto
#    Mod+Ctrl+V (matching the Bluetooth/Wifi controls). Strip the old marker
#    block (whatever it contained) and re-append the current one.
USER_KDL="$HOME/.config/niri/user.kdl"
if [[ -f "$USER_KDL" ]] && grep -q 'monarch:lazyvpn:begin' "$USER_KDL"; then
  echo "  Updating the Niri keybinding to Mod+Ctrl+V (monarch-lazyvpn)..."
  sed -i '/\/\/ monarch:lazyvpn:begin/,/\/\/ monarch:lazyvpn:end/d' "$USER_KDL"
  cat >>"$USER_KDL" <<'EOF'

// monarch:lazyvpn:begin
binds {
    Mod+Ctrl+V hotkey-overlay-title="LazyVPN controls" { spawn "monarch-launch-floating-terminal-with-presentation" "monarch-lazyvpn"; }
}
// monarch:lazyvpn:end
EOF
  if pgrep -x niri >/dev/null 2>&1; then
    niri msg action reload-config >/dev/null 2>&1 || true
  fi
fi

# 2. (Re)create the app-launcher entry. The new package ships only the binaries.
echo "  Refreshing the 'LazyVPN' app-launcher entry..."
DESKTOP_FILE="$HOME/.local/share/applications/LazyVPN.desktop"
cat >"$DESKTOP_FILE" <<'EOF'
[Desktop Entry]
Version=1.0
Name=LazyVPN
Comment=TUI WireGuard multi-provider VPN manager
Exec=monarch-launch-floating-terminal-with-presentation monarch-lazyvpn
Terminal=false
Type=Application
Icon=network-vpn
StartupNotify=true
EOF
chmod +x "$DESKTOP_FILE"

# 3. Add the Noctalia bar status widget. Idempotent: skip if a
#    monarch-lazyvpn-status button already exists. Noctalia hot-reloads
#    settings.json, so the bar picks the change up without a restart.
NOCTALIA_CFG="$HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null && [[ -f "$NOCTALIA_CFG" ]]; then
  if ! jq -e '[.. | objects | select(.textCommand? == "monarch-lazyvpn-status")] | length > 0' \
       "$NOCTALIA_CFG" >/dev/null 2>&1; then
    echo "  Adding the LazyVPN status widget to the Noctalia bar..."
    tmp=$(mktemp)
    if jq '.bar.widgets.right = ([{
             "id": "CustomButton",
             "icon": "shield",
             "parseJson": true,
             "textCommand": "monarch-lazyvpn-status",
             "textIntervalMs": 5000,
             "leftClickExec": "monarch-launch-floating-terminal-with-presentation monarch-lazyvpn"
           }] + (.bar.widgets.right // []))' \
         "$NOCTALIA_CFG" >"$tmp"; then
      mv "$tmp" "$NOCTALIA_CFG"
    else
      rm -f "$tmp"
      echo "  Warning: could not update $NOCTALIA_CFG; add the widget manually." >&2
    fi
  fi
fi
