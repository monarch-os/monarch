echo "Drop linux-ptl (the CachyOS kernel now covers Panther Lake)"

# linux-ptl was an [omarchy]-only kernel shipped to Dell XPS Panther Lake to
# carry audio/i915 patches not yet in mainline. With the Omarchy repo gone it
# can no longer receive updates, and the CachyOS kernel now carries the Panther
# Lake patches. Move any install still on linux-ptl back to the stock
# linux-cachyos-lts kernel.

if monarch-pkg-present linux-ptl; then
  # 1. Guarantee a maintained kernel (+ headers for DKMS) is in place before
  #    removing linux-ptl, so the machine never ends up without a bootable one.
  monarch-pkg-add linux-cachyos-lts linux-cachyos-lts-headers

  # 2. sof-firmware was a hard-dep of linux-ptl; linux-cachyos-lts only optdeps
  #    it. Mark it explicit so the orphan sweep can't reclaim it and kill the
  #    Panther Lake audio DSP.
  if monarch-pkg-present sof-firmware; then
    sudo pacman -D --asexplicit sof-firmware >/dev/null
  fi

  # 3. Remove the now-unmaintainable kernel.
  for pkg in linux-ptl linux-ptl-headers; do
    sudo pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
  done

  # 4. Drop the linux-ptl-only boot ordering so limine falls back to the
  #    default linux-cachyos-lts entry.
  sudo rm -f /etc/limine-entry-tool.d/dell-xps-panther-lake.conf

  if monarch-cmd-present limine-update; then
    sudo limine-update
  fi

  monarch-state set reboot-required
fi
