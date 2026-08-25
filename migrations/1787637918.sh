echo "Synchronize SDDM with the active Noctalia palette"

rm -f "$HOME/.config/noctalia/templates/sddm.conf"
rmdir "$HOME/.config/noctalia/templates" 2>/dev/null || true

if [[ -w /usr/share/sddm/themes/monarch/theme.conf && -w /usr/share/sddm/themes/monarch/logo.png ]]; then
  monarch-sddm-apply
else
  monarch-refresh-sddm
fi
