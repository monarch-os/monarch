for browser_flags in \
  "$HOME/.config/chromium-flags.conf" \
  "$HOME/.config/brave-flags.conf" \
  "$HOME/.config/chrome-flags.conf" \
  "$HOME/.config/microsoft-edge-stable-flags.conf"; do
  [[ -f $browser_flags ]] || continue
  grep -Eq '^[[:space:]]*--password-store(=|[[:space:]])' "$browser_flags" && continue

  [[ -z $(tail -c1 "$browser_flags") ]] || printf '\n' >>"$browser_flags"
  printf '%s\n' '--password-store=gnome-libsecret' >>"$browser_flags"
done
