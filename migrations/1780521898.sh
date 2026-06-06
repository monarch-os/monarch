echo "LUKS keymap: embed /etc/vconsole.conf in the initramfs so Plymouth reads the configured layout"

conf=/etc/mkinitcpio.conf.d/monarch_hooks.conf

if command -v limine &>/dev/null && [[ -f $conf ]]; then
  if ! grep -q '^FILES=.*vconsole.conf' "$conf"; then
    echo 'FILES=(/etc/vconsole.conf)' | sudo tee -a "$conf" >/dev/null

    if monarch-cmd-present limine-update; then
      sudo limine-update
    fi
  fi
else
  echo "Non-limine or unmanaged boot config. Not making any changes."
fi
