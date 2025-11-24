# Copy over Monarch configs
mkdir -p ~/.config
cp -R ~/.local/share/monarch/config/* ~/.config/

# Use default RC from Monarch
cp ~/.local/share/monarch/default/bashrc ~/.bashrc

# Install ZSH
cp ~/.local/share/monarch/default/zshrc ~/.zshrc

# Change shell
sudo chsh -s /bin/zsh ${USER}