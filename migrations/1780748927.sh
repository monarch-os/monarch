echo "Repair the Noctalia sddm user-template (missing input + non-writable output)"

# Migration 1779188617 deployed noctalia/user-templates.toml (which registers
# [templates.sddm]: input ~/.config/noctalia/templates/sddm.conf -> output
# /usr/share/sddm/themes/monarch/theme.conf) but never finished wiring it up for
# updating installs, so Noctalia fails on every color generation. Two facets,
# both fixed forward here since that migration already ran and can't be replayed:
#
#   1. The input template was never seeded -> "Template file not found".
#   2. monarch-refresh-sddm (which installs the current theme AND chmod 666's
#      theme.conf/logo.png so Noctalia can rewrite them in place) never ran, so
#      the shipped theme.conf stays root-owned 0644 -> "Permission denied".
#
# Guarded on the registry actually referencing the sddm template so we never
# touch a customized setup that removed it.

registry="$HOME/.config/noctalia/user-templates.toml"
sddm_input="$HOME/.config/noctalia/templates/sddm.conf"
sddm_output="/usr/share/sddm/themes/monarch/theme.conf"

if [[ -f $registry ]] && grep -q '\[templates.sddm\]' "$registry"; then
  # 1. Seed the input template if it's missing.
  if [[ ! -f $sddm_input ]]; then
    echo "Seeding $sddm_input from Monarch defaults."
    monarch-refresh-config noctalia/templates/sddm.conf || true
  fi

  # 2. Make the output installable + writable by Noctalia (runs as the user).
  #    Refresh whenever theme.conf is absent or not user-writable.
  if command -v monarch-refresh-sddm >/dev/null 2>&1 && [[ ! -w $sddm_output ]]; then
    echo "Reinstalling the SDDM theme so Noctalia can rewrite $sddm_output."
    monarch-refresh-sddm || true
  fi
else
  echo "sddm template not registered. Nothing to do."
fi
