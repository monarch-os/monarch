#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

sudo_available() {
  sudo -n true 2>/dev/null && return 0
  [[ -n ${MONARCH_ACCEPTANCE_SUDO_PASSWORD:-} ]] || return 1
  printf '%s\n' "$MONARCH_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -v 2>/dev/null
}

if id -nG | grep -qw input; then
  pacman -Qq ydotool >/dev/null 2>&1 ||
    fail "input group membership requires the explicit ydotool opt-in"
fi
pass "input group membership follows the explicit opt-in"

if ! sudo_available; then
  fail "privileged acceptance checks can authenticate with sudo"
fi

for retired in asdcontrol monarch-asdcontrol omarchy-asdcontrol first-run \
  99-monarch-installer-reboot tsui; do
  ! sudo -n test -e "/etc/sudoers.d/$retired" ||
    fail "retired sudoers grants are absent" "/etc/sudoers.d/$retired"
done
pass "retired sudoers grants are absent"

for sudoers in monarch-dns monarch-theme-browser monarch-tzupdate; do
  metadata=$(sudo -n stat -Lc '%U:%G %a' "/etc/sudoers.d/$sudoers") ||
    fail "shipped sudoers metadata can be read" "$sudoers"
  [[ $metadata == "root:root 440" ]] ||
    fail "shipped sudoers grants are protected" "$sudoers: $metadata"
done
pass "shipped sudoers grants are protected"

if pacman -Q cups-browsed >/dev/null 2>&1 ||
  systemctl is-active --quiet cups-browsed.service 2>/dev/null ||
  pgrep -x cups-browsed >/dev/null 2>&1; then
  fail "automatic printer discovery is absent"
fi
systemctl is-active --quiet cups.service || fail "CUPS is running"
timeout 10 lpstat -r >/dev/null 2>&1 || fail "CUPS answers locally"
pass "printing runs without automatic discovery"

for published in \
  /usr/share/plymouth/themes/monarch/monarch.script \
  /usr/share/sddm/themes/monarch/theme.conf \
  /usr/share/sddm/themes/monarch/logo.png \
  /etc/sddm.conf.d/10-theme.conf; do
  assert_root_file "$published" 644
done
pass "Plymouth and SDDM inputs are protected"

key_file="$ARTIFACTS/sshd-key"
rm -f "$key_file" "$key_file.pub"
ssh-keygen -t ed25519 -N "" -q -C "monarch-acceptance" -f "$key_file"

if ! MONARCH_ACCEPTANCE_SUDO_PASSWORD="$MONARCH_ACCEPTANCE_SUDO_PASSWORD" \
  MONARCH_ACCEPTANCE_SSHD_KEY="$(<"$key_file.pub")" SHELL=/bin/bash \
  script -qec 'printf "%s\n" "$MONARCH_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -v 2>/dev/null &&
    monarch-setup-security-sshd --key="$MONARCH_ACCEPTANCE_SSHD_KEY"' /dev/null \
  </dev/null >"$ARTIFACTS/setup-security-sshd.log" 2>&1; then
  fail "SSH hardening completes unattended" "$(tail -5 "$ARTIFACTS/setup-security-sshd.log")"
fi
pass "SSH hardening completes unattended"

effective=$(sudo -n sshd -T) || fail "sshd reports its effective configuration"
grep -qixF "passwordauthentication no" <<<"$effective" || fail "SSH password authentication is disabled"
grep -qixF "kbdinteractiveauthentication no" <<<"$effective" ||
  fail "SSH keyboard-interactive authentication is disabled"
sudo -n env LC_ALL=C ufw status | awk '$1 == "22/tcp" && $2 == "LIMIT" { found = 1 } END { exit !found }' ||
  fail "SSH is rate-limited by UFW"
pass "SSH exposes only key authentication behind rate limiting"

key_body=$(cut -d' ' -f2 "$key_file.pub")
sed -i "\\|$key_body|d" "$HOME/.ssh/authorized_keys"
rm -f "$key_file" "$key_file.pub"
