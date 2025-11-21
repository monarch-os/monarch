echo "Change SSHM and screenshots keybindings"


sed -i '/bindd = SUPER SHIFT, S, SSH Manager, exec, monarch-launch-floating-terminal-with-presentation sshm/d' ~/.config/hypr/bindings.conf
sed -i '/bindd = CTRL ALT, E, Exegol, exec, setsid uwsm-app -- monarch-menu-exegol/a \
bindd = CTRL ALT, S, SSH Manager, exec, monarch-launch-floating-terminal-with-presentation sshm' ~/.config/hypr/bindings.conf
