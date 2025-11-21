echo "Add Outlook to webapps"

cp -f $MONARCH_PATH/applications/icons/Outlook.png ~/.local/share/applications/icons/
monarch-webapp-install "Outlook" https://outlook.office.com Outlook.png
