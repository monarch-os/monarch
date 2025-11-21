echo "Migrate to Walker 2.0.0"

# Ensure we kill walker even if there's a restarting service running
kill -9 $(pgrep -x walker)

monarch-pkg-drop walker-bin walker-bin-debug

monarch-pkg-add elephant \
  elephant-calc \
  elephant-clipboard \
  elephant-bluetooth \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-runner \
  elephant-symbols \
  elephant-unicode \
  elephant-websearch \
  elephant-todo \
  walker

source $MONARCH_PATH/install/config/walker-elephant.sh

rm -rf ~/.config/walker/themes
monarch-refresh-walker