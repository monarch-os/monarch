echo "Add Tmux as an option with themed styling"

monarch-pkg-add tmux

if [[ ! -f ~/.config/tmux/tmux.conf ]]; then
  mkdir -p ~/.config/tmux
  cp $MONARCH_PATH/config/tmux/tmux.conf ~/.config/tmux/tmux.conf
fi
