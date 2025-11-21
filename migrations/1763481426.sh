echo "Add Whatsapp and SploitUS apps"

cp -f $MONARCH_PATH/applications/icons/WhatsApp.png ~/.local/share/applications/icons/
cp -f $MONARCH_PATH/applications/icons/Sploitus.png ~/.local/share/applications/icons/

monarch-webapp-install "WhatsApp" https://web.whatsapp.com/ WhatsApp.png
monarch-webapp-install "SploitUS" https://sploitus.com/ Sploitus.png
