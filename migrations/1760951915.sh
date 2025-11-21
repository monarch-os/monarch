echo -e "Offer new Monarch hotkeys and add cyberchef\n"

cat <<EOF
* Move app keys from SUPER + [LETTER] to SHIFT + SUPER + [LETTER]
EOF

echo -e "\nSwitching to new hotkeys will change your existing bindings.\nThe old ones will be backed up as ~/.config/hypr/bindings.conf.bak\n"

if gum confirm "Switch to new hotkeys?"; then
    cp ~/.config/hypr/bindings.conf ~/.config/hypr/bindings.conf.bak

    sed -i 's/SUPER,/SUPER SHIFT,/g' ~/.config/hypr/bindings.conf
    sed -i 's/SUPER SHIFT, return, Terminal/SUPER, RETURN, Terminal/gI' ~/.config/hypr/bindings.conf
    sed -i '/bindd = SUPER SHIFT, E, Email, exec, monarch-launch-webapp "https:\/\/outlook\.office\.com"/a bindd = SUPER SHIFT, C, Cyberchef, exec, monarch-launch-webapp "https://gchq.github.io/CyberChef/"' ~/.config/hypr/bindings.conf
fi


cp -f $MONARCH_PATH/applications/icons/Cyberchef.png ~/.local/share/applications/icons/
monarch-webapp-install "Cyberchef" "https://gchq.github.io/CyberChef/" Cyberchef.png

