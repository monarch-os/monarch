echo "Remove Zoom and install Teams"

monarch-webapp-remove Zoom

cp -f $MONARCH_PATH/applications/icons/Teams.png ~/.local/share/applications/icons/
monarch-webapp-install "Teams" https://teams.microsoft.com/ Teams.png
