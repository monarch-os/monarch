# Copy over Monarch configs
mkdir -p ~/.config
cp -R ~/.local/share/monarch/config/* ~/.config/

# Use default RC from Monarch
cp ~/.local/share/monarch/default/bashrc ~/.bashrc

# Install ZSH & Oh My ZSH
cp ~/.local/share/monarch/default/zshrc ~/.zshrc
[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 700 ~/.ssh # Must exist for ssh-agent to work
for plugin in colored-man-pages docker extract fzf mise npm terraform tmux zsh-autosuggestions zsh-completions zsh-syntax-highlighting ssh-agent z ; do zsh -c "source ~/.zshrc && omz plugin enable $plugin || true"; done

# Change shell
sudo chsh -s /bin/zsh ${USER}