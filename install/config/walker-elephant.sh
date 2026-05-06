#!/bin/bash

# Ensure Walker service is started automatically on boot
mkdir -p ~/.config/autostart/
cp $MONARCH_PATH/default/walker/walker.desktop ~/.config/autostart/

# And is restarted if it crashes or is killed
mkdir -p ~/.config/systemd/user/app-walker@autostart.service.d/
cp $MONARCH_PATH/default/walker/restart.conf ~/.config/systemd/user/app-walker@autostart.service.d/restart.conf

# Create pacman hook to restart walker after updates
sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/walker-restart.hook > /dev/null << EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = walker
Target = walker-debug
Target = elephant*

[Action]
Description = Restarting Walker services after system update
When = PostTransaction
Exec = $MONARCH_PATH/bin/monarch-restart-walker
EOF

# Link the visual theme menu config
mkdir -p ~/.config/elephant/menus
ln -snf $MONARCH_PATH/default/elephant/monarch_themes.lua ~/.config/elephant/menus/monarch_themes.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_background_selector.lua ~/.config/elephant/menus/monarch_background_selector.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_exegol.lua ~/.config/elephant/menus/monarch_exegol.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_rfswift.lua ~/.config/elephant/menus/monarch_rfswift.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_pentestenv.lua ~/.config/elephant/menus/monarch_pentestenv.lua
ln -snf $MONARCH_PATH/default/elephant/monarch_unlocks.lua ~/.config/elephant/menus/monarch_unlocks.lua
