# Noctalia drives external monitor brightness over DDC/CI, which means writing
# to /dev/i2c-*. The ddcutil package leaves those root:i2c 0660 and loads
# i2c-dev, but nothing puts the user in the group — so the brightness slider
# reached the laptop panel and silently nothing else.
sudo usermod -aG i2c ${USER}
