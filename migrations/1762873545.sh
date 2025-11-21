pkill elephant
elephant service enable
systemctl --user start elephant.service

pkill walker
mkdir -p ~/.config/autostart/
cp $MONARCH_PATH/autostart/walker.desktop ~/.config/autostart/
setsid walker --gapplication-service &
