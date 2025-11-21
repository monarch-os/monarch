echo "Install swayOSD to show volume status"

if monarch-cmd-missing swayosd-server; then
  monarch-pkg-add swayosd
  setsid uwsm-app -- swayosd-server &>/dev/null &
fi