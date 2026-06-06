# Set links for Nautilus action icons
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

# Chromium policy directory for the residual theme layer. monarch-theme-apply
# writes BrowserThemeColor here; made world-writable so it needs no sudo at runtime.
sudo mkdir -p /etc/chromium/policies/managed
sudo chmod a+rw /etc/chromium/policies/managed

# Default Chromium to follow system appearance ("device") instead of dark
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null
rm -rf ~/.config/chromium/SingletonLock # otherwise archiso will own the chromium singleton

# Theming is delegated to Noctalia (colors, dark/light, templates). The shipped
# Monarch scheme and settings.json are already in place via config.sh. Apply the
# residual system layer once (seeds the wallpaper folder, themes Chromium/keyboard).
monarch-theme-apply
