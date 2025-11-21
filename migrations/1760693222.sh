echo "Use explicit timezone selector when right-clicking on clock"

sed -i 's/monarch-cmd-tzupdate/monarch-launch-floating-terminal-with-presentation monarch-tz-select/g' ~/.config/waybar/config.jsonc