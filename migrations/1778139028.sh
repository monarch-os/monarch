echo "Add weather widget to Waybar"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"

if [[ -f $WAYBAR_CONFIG ]] && ! grep -q '"custom/weather"' "$WAYBAR_CONFIG"; then
  # Single-line modules-center: "modules-center": ["clock", ...]
  sed -i 's/"modules-center": \["clock",/"modules-center": ["clock", "custom\/weather",/' "$WAYBAR_CONFIG"
  # Multi-line modules-center: standalone "clock", array element
  if ! grep -q '"custom/weather"' "$WAYBAR_CONFIG"; then
    sed -i 's|^\(\s*\)"clock",$|\1"clock",\n\1"custom/weather",|' "$WAYBAR_CONFIG"
  fi
  sed -i '/"network": {/i\  "custom/weather": {\n    "exec": "$MONARCH_PATH/default/waybar/weather.sh",\n    "return-type": "json",\n    "interval": 60,\n    "tooltip": false,\n    "on-click": "notify-send -u low \\"$(monarch-weather-status)\\""\n  },' "$WAYBAR_CONFIG"
fi

if [[ -f $WAYBAR_STYLE ]] && ! grep -q '#custom-weather' "$WAYBAR_STYLE"; then
  cat >>"$WAYBAR_STYLE" <<'EOF'
#custom-weather {
  margin-left: 7.5px;
  margin-right: 7.5px;
}
#custom-weather.unavailable {
  min-width: 0;
  margin: 0;
  padding: 0;
}
EOF
fi

monarch-restart-waybar
