# Set links for Nautilius action icons
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

# Setup theme links
mkdir -p ~/.config/monarch/themes
for f in ~/.local/share/monarch/themes/*; do ln -nfs "$f" ~/.config/monarch/themes/; done

# Set initial theme
mkdir -p ~/.config/monarch/current
ln -snf ~/.config/monarch/themes/monarch ~/.config/monarch/current/theme
ln -snf ~/.config/monarch/current/theme/backgrounds/1-background.png ~/.config/monarch/current/background

# Set specific app links for current theme
# ~/.config/monarch/current/theme/neovim.lua -> ~/.config/nvim/lua/plugins/theme.lua is handled via monarch-setup-nvim

mkdir -p ~/.config/btop/themes
ln -snf ~/.config/monarch/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/monarch/current/theme/mako.ini ~/.config/mako/config

# Add managed policy directories for Chromium and Brave for theme changes
sudo mkdir -p /etc/chromium/policies/managed
sudo chmod a+rw /etc/chromium/policies/managed

sudo mkdir -p /etc/brave/policies/managed
sudo chmod a+rw /etc/brave/policies/managed
